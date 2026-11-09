// Cost semantics adapted from farion1231/cc-switch (MIT).
// Copyright (c) 2025 Jason Young. See Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
use crate::{UsageRecord, UsageTokens};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{collections::BTreeMap, str::FromStr};

pub const BUNDLED_PRICE_DATE: &str = "2026-11-09";

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct TokenRates {
    pub input: Option<Decimal>,
    pub output: Option<Decimal>,
    pub cached: Option<Decimal>,
    pub cache_write: Option<Decimal>,
    pub cache_write_long: Option<Decimal>,
}

impl TokenRates {
    pub fn is_valid(&self) -> bool {
        [
            self.input,
            self.output,
            self.cached,
            self.cache_write,
            self.cache_write_long,
        ]
        .iter()
        .all(|price| {
            price.is_none_or(|v| v >= Decimal::ZERO && v < Decimal::from(1_000_000_000u64))
        })
    }
    pub fn cost(&self, tokens: &UsageTokens) -> Option<Decimal> {
        if [
            self.input,
            self.output,
            self.cached,
            self.cache_write,
            self.cache_write_long,
        ]
        .iter()
        .all(Option::is_none)
        {
            return None;
        }
        let parts = [
            (tokens.input, self.input),
            (tokens.output, self.output),
            (tokens.cached, self.cached),
            (
                tokens.cache_write - tokens.cache_write_long,
                self.cache_write,
            ),
            (tokens.cache_write_long, self.cache_write_long),
        ];
        let mut result = Decimal::ZERO;
        for (count, price) in parts {
            if count > 0 {
                result += Decimal::from(count) * price? / Decimal::from(1_000_000u64);
            }
        }
        Some(result)
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ModelPricing {
    pub service: String,
    pub model: String,
    pub rates: TokenRates,
    pub context_threshold: Option<u64>,
    pub long_context_rates: Option<TokenRates>,
    pub fast_multiplier: Option<Decimal>,
    pub ultrafast_multiplier: Option<Decimal>,
}

impl ModelPricing {
    pub fn key(&self) -> String {
        format!("{}:{}", self.service, self.model.to_lowercase())
    }
    pub fn is_valid(&self) -> bool {
        !self.model.trim().is_empty()
            && self.rates.is_valid()
            && self
                .long_context_rates
                .as_ref()
                .is_none_or(TokenRates::is_valid)
            && self
                .context_threshold
                .is_none_or(|v| v > 0 && v < 100_000_000)
            && [self.fast_multiplier, self.ultrafast_multiplier]
                .iter()
                .all(|value| value.is_none_or(|v| v > Decimal::ZERO && v < Decimal::from(1000u32)))
    }
    pub fn cost(&self, record: &UsageRecord) -> Option<Decimal> {
        if record.service != self.service || !record.tokens.complete() {
            return None;
        }
        // Native agy does not report cache-write TTL; do not silently price it as short-lived.
        if record.service == "antigravity" && record.tokens.cache_write > 0 {
            return None;
        }
        let incoming = record.tokens.input + record.tokens.cached + record.tokens.cache_write;
        let rates = if self
            .context_threshold
            .is_some_and(|threshold| incoming > threshold)
        {
            self.long_context_rates.as_ref()?
        } else {
            &self.rates
        };
        let multiplier = if record.service == "antigravity" {
            Decimal::ONE
        } else {
            match record.service_tier.as_str() {
                "standard" | "default" | "auto" => Decimal::ONE,
                "fast" | "priority" => self.fast_multiplier?,
                "ultrafast" => self.ultrafast_multiplier?,
                _ => return None,
            }
        };
        Some(rates.cost(&record.tokens)? * multiplier)
    }
}

pub fn price_record(
    record: &UsageRecord,
    prices: &BTreeMap<String, ModelPricing>,
) -> Option<Decimal> {
    if record.model == "unknown" {
        return None;
    }
    lookup_price(&record.service, &record.model, prices)?.cost(record)
}

pub fn lookup_price<'a>(
    service: &str,
    model: &str,
    prices: &'a BTreeMap<String, ModelPricing>,
) -> Option<&'a ModelPricing> {
    if !["codex", "antigravity"].contains(&service) {
        return None;
    }
    let raw = model.trim().to_lowercase();
    if let Some(price) = prices.get(&format!("{service}:{raw}")) {
        return Some(price);
    }
    let name = raw
        .strip_prefix("openai/")
        .or_else(|| {
            (service == "antigravity")
                .then(|| {
                    raw.strip_prefix("google/")
                        .or_else(|| raw.strip_prefix("anthropic/"))
                })
                .flatten()
        })
        .unwrap_or(&raw);
    if let Some(price) = prices.get(&format!("{service}:{name}")) {
        return Some(price);
    }
    // 只移除日期后缀，不把未知模型别名映射到已知价格。
    for length in [9, 10, 11] {
        if name.len() < length {
            continue;
        }
        let Some(suffix) = name.get(name.len() - length..) else {
            continue;
        };
        let Some(date) = suffix.strip_prefix('-') else {
            continue;
        };
        let valid = match date.len() {
            8 => date.bytes().all(|b| b.is_ascii_digit()),
            9 => [4, 6].into_iter().any(|separator| {
                date.bytes().enumerate().all(|(i, b)| {
                    if i == separator {
                        b == b'-'
                    } else {
                        b.is_ascii_digit()
                    }
                })
            }),
            10 => date.bytes().enumerate().all(|(i, b)| {
                if i == 4 || i == 7 {
                    b == b'-'
                } else {
                    b.is_ascii_digit()
                }
            }),
            _ => false,
        };
        if valid {
            return prices.get(&format!("{service}:{}", &name[..name.len() - length]));
        }
    }
    None
}

pub fn decode_catalog(data: &[u8]) -> Result<BTreeMap<String, ModelPricing>, String> {
    let root: Value = serde_json::from_slice(data).map_err(|_| "价格数据无效，已保留原有价格。")?;
    root.pointer("/openai/models")
        .and_then(Value::as_object)
        .filter(|models| !models.is_empty())
        .ok_or("价格数据无效，已保留原有价格。")?;
    let mut result = BTreeMap::new();
    for (provider, service) in [
        ("openai", "codex"),
        ("google", "antigravity"),
        ("anthropic", "antigravity"),
        ("openai", "antigravity"),
    ] {
        let Some(models) = root
            .get(provider)
            .and_then(|v| v.get("models"))
            .and_then(Value::as_object)
        else {
            continue;
        };
        for (name, model) in models {
            let Some(cost) = model.get("cost").filter(|v| v.is_object()) else {
                continue;
            };
            if model
                .pointer("/modalities/output")
                .is_some_and(|output| output != &serde_json::json!(["text"]))
            {
                continue;
            }
            let rates = decode_rates(cost);
            if rates.input.is_none() || rates.output.is_none() {
                continue;
            }
            let mut price = ModelPricing {
                service: service.into(),
                model: name.clone(),
                rates,
                context_threshold: None,
                long_context_rates: None,
                fast_multiplier: None,
                ultrafast_multiplier: None,
            };
            let context = cost
                .get("tiers")
                .and_then(Value::as_array)
                .and_then(|tiers| {
                    tiers.iter().find(|tier| {
                        tier.pointer("/tier/type").and_then(Value::as_str) == Some("context")
                    })
                });
            if let Some((context, threshold)) = context.and_then(|v| {
                v.pointer("/tier/size")
                    .and_then(Value::as_u64)
                    .filter(|n| *n > 0)
                    .map(|n| (v, n))
            }) {
                price.context_threshold = Some(threshold);
                price.long_context_rates = Some(decode_rates(context));
            } else if let Some(long) = cost.get("context_over_200k").filter(|v| v.is_object()) {
                price.context_threshold = Some(200_000);
                price.long_context_rates = Some(decode_rates(long));
            }
            if price.is_valid() {
                result.insert(price.key(), price);
            }
        }
    }
    if result.is_empty() {
        return Err("价格数据无效，已保留原有价格。".into());
    }
    Ok(result)
}

fn decode_rates(value: &Value) -> TokenRates {
    let rate = |key| {
        value
            .get(key)
            .and_then(Value::as_number)
            .and_then(|n| Decimal::from_str(&n.to_string()).ok())
            .filter(|n| *n >= Decimal::ZERO && *n < Decimal::from(1_000_000_000u64))
    };
    let write = rate("cache_write");
    TokenRates {
        input: rate("input"),
        output: rate("output"),
        cached: rate("cache_read"),
        cache_write: write,
        cache_write_long: rate("cache_write_long"),
    }
}

pub fn bundled_prices() -> BTreeMap<String, ModelPricing> {
    // Retain the older catalog for historical models absent from current official pages.
    let mut prices = decode_catalog(include_bytes!("pricing-catalog.json")).expect("legacy model price catalog");
    prices.extend(official_prices());
    prices
}

pub fn official_prices() -> BTreeMap<String, ModelPricing> {
    serde_json::from_slice(include_bytes!("official-pricing.json")).expect("official model price catalog")
}
