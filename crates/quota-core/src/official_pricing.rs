use crate::{ModelPricing, TokenRates};
use chrono::NaiveDate;
use rust_decimal::Decimal;
use std::{collections::BTreeMap, str::FromStr};

pub const OFFICIAL_PRICE_SOURCES: [(&str, &str); 3] = [
    (
        "openai",
        "https://developers.openai.com/api/docs/pricing.md",
    ),
    ("google", "https://ai.google.dev/gemini-api/docs/pricing"),
    (
        "anthropic",
        "https://platform.claude.com/docs/en/about-claude/pricing.md",
    ),
];

pub fn decode_official_prices(
    provider: &str,
    text: &str,
    date: NaiveDate,
) -> Result<BTreeMap<String, ModelPricing>, String> {
    let mut prices = BTreeMap::new();
    match provider {
        "openai" => {
            let standard = section(text, "### Standard pricing data", "### Batch pricing data")?;
            for cells in table_rows(standard) {
                if let Some(price) = openai_row(&cells) {
                    prices.insert(price.key(), price);
                }
            }
            for (heading, next, ultrafast) in [
                ("### Fast pricing data", "### Ultrafast pricing data", false),
                ("### Ultrafast pricing data", "Short context:", true),
            ] {
                for cells in table_rows(section(text, heading, next)?) {
                    let Some(tier) = openai_row(&cells) else {
                        continue;
                    };
                    let Some(base) = prices.get_mut(&tier.key()) else {
                        continue;
                    };
                    let factor = tier
                        .rates
                        .input
                        .zip(base.rates.input)
                        .filter(|(_, input)| *input > Decimal::ZERO)
                        .map(|(rate, input)| rate / input);
                    let factor = factor.filter(|factor| {
                        same_multiplier(&base.rates, &tier.rates, *factor)
                            && match (&base.long_context_rates, &tier.long_context_rates) {
                                (Some(base), Some(tier)) => same_multiplier(base, tier, *factor),
                                (None, None) => true,
                                _ => false,
                            }
                    });
                    if ultrafast {
                        base.ultrafast_multiplier = factor;
                    } else {
                        base.fast_multiplier = factor;
                    }
                }
            }
            let specialized = text
                .split_once("Specialized models")
                .ok_or("缺少 OpenAI 专用模型价格。")?
                .1;
            for cells in table_rows(specialized) {
                if cells.len() != 5 || cells[0] != "Codex" {
                    continue;
                }
                let Some(mut price) = openai_row(&cells[1..]) else {
                    continue;
                };
                if let Some(base) = prices.get_mut(&price.key()) {
                    let factor = price
                        .rates
                        .input
                        .zip(base.rates.input)
                        .filter(|(_, input)| *input > Decimal::ZERO)
                        .map(|(rate, input)| rate / input)
                        .filter(|factor| same_multiplier(&base.rates, &price.rates, *factor));
                    base.fast_multiplier = factor;
                } else {
                    price.fast_multiplier = None;
                    prices.insert(price.key(), price);
                }
            }
            let antigravity: Vec<_> = prices
                .values()
                .cloned()
                .map(|mut price| {
                    price.service = "antigravity".into();
                    price.fast_multiplier = None;
                    price.ultrafast_multiplier = None;
                    price
                })
                .collect();
            prices.extend(antigravity.into_iter().map(|price| (price.key(), price)));
        }
        "google" => {
            // Only text-generation models with the documented Standard paid tier.
            for model in [
                "gemini-4-argon",
                "gemini-3.8-flash",
                "gemini-3.6-flash",
                "gemini-3.5-flash-lite",
                "gemini-3.1-flash-lite",
                "gemini-3.1-pro-preview",
                "gemini-3-flash-preview",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
            ] {
                let marker = format!("id=\"{model}\"");
                let Some((_, rest)) = text.split_once(&marker) else {
                    continue;
                };
                let model_text = rest.split("\n## ").next().unwrap_or(rest);
                let standard = section(model_text, "{% tab title=\"Standard\" %}", "{% /table %}")?;
                let input = google_rate(standard, "Input price", date)?;
                let output = google_rate(standard, "Output price", date)?;
                let cached = google_rate(standard, "Context caching price", date)?;
                let mut price = blank_price("antigravity", model);
                price.rates = TokenRates {
                    input: input.0,
                    output: output.0,
                    cached: cached.0,
                    ..Default::default()
                };
                if input.1.is_some() {
                    price.context_threshold = Some(200_000);
                    price.long_context_rates = Some(TokenRates {
                        input: input.1,
                        output: output.1,
                        cached: cached.1,
                        ..Default::default()
                    });
                }
                if model == "gemini-3.1-pro-preview" {
                    let mut customtools = price.clone();
                    customtools.model = "gemini-3.1-pro-preview-customtools".into();
                    prices.insert(customtools.key(), customtools);
                }
                prices.insert(price.key(), price);
            }
        }
        "anthropic" => {
            for cells in table_rows(section(
                text,
                "## Model pricing",
                "## Cloud platform pricing",
            )?) {
                if cells.len() != 6 || !cells[0].starts_with("Claude ") {
                    continue;
                }
                let name = cells[0].split(" (").next().unwrap_or(cells[0]);
                let model = name.to_lowercase().replace([' ', '.'], "-");
                let mut price = blank_price("antigravity", &model);
                price.rates = TokenRates {
                    input: dollar(cells[1]),
                    output: dollar(cells[5]),
                    cached: dollar(cells[4]),
                    cache_write: dollar(cells[2]),
                    cache_write_long: dollar(cells[3]),
                };
                if cells[0].contains("over 100,000 tokens") {
                    let base: &mut ModelPricing = prices
                        .get_mut(&price.key())
                        .ok_or("Claude 长上下文价格缺少标准价。")?;
                    base.context_threshold = Some(100_000);
                    base.long_context_rates = Some(price.rates);
                } else {
                    prices.insert(price.key(), price);
                }
            }
        }
        _ => return Err("未知价格来源。".into()),
    }
    if prices.is_empty()
        || prices.values().any(|price| {
            !price.is_valid() || price.rates.input.is_none() || price.rates.output.is_none()
        })
    {
        return Err(format!("{provider} 官方价格格式已变化，已保留原有价格。"));
    }
    Ok(prices)
}

fn blank_price(service: &str, model: &str) -> ModelPricing {
    ModelPricing {
        service: service.into(),
        model: model.into(),
        rates: TokenRates::default(),
        context_threshold: None,
        long_context_rates: None,
        fast_multiplier: None,
        ultrafast_multiplier: None,
    }
}

fn section<'a>(text: &'a str, start: &str, end: &str) -> Result<&'a str, String> {
    text.split_once(start)
        .and_then(|(_, rest)| rest.split_once(end).map(|(value, _)| value))
        .ok_or_else(|| "官方价格页面格式已变化，已保留原有价格。".into())
}

fn table_rows(text: &str) -> impl Iterator<Item = Vec<&str>> {
    text.lines()
        .filter(|line| line.starts_with('|'))
        .map(|line| line.trim_matches('|').split('|').map(str::trim).collect())
}

fn dollar(text: &str) -> Option<Decimal> {
    let value = text.trim().strip_prefix('$')?;
    let end = value
        .find(|c: char| !c.is_ascii_digit() && c != '.')
        .unwrap_or(value.len());
    Decimal::from_str(&value[..end]).ok()
}

fn openai_row(cells: &[&str]) -> Option<ModelPricing> {
    if ![4, 11].contains(&cells.len())
        || !["gpt-", "o1", "o3", "o4"]
            .iter()
            .any(|prefix| cells[0].starts_with(prefix))
    {
        return None;
    }
    let model = cells[0].split_whitespace().next()?;
    let rates = |row: &[&str]| TokenRates {
        input: dollar(row[0]),
        output: dollar(row[1]),
        cached: dollar(row[2]),
        cache_write: row.get(3).and_then(|value| dollar(value)),
        cache_write_long: row.get(4).and_then(|value| dollar(value)),
    };
    let mut price = blank_price("codex", model);
    price.rates = rates(&cells[1..]);
    if cells.len() == 11 && dollar(cells[6]).is_some() {
        price.context_threshold = Some(272_000);
        price.long_context_rates = Some(rates(&cells[6..]));
    }
    Some(price)
}

fn same_multiplier(base: &TokenRates, tier: &TokenRates, factor: Decimal) -> bool {
    [
        base.input,
        base.output,
        base.cached,
        base.cache_write,
        base.cache_write_long,
    ]
    .into_iter()
    .zip([
        tier.input,
        tier.output,
        tier.cached,
        tier.cache_write,
        tier.cache_write_long,
    ])
    .all(|(base, tier)| base.map(|value| value * factor) == tier)
}

fn google_rate(
    table: &str,
    label: &str,
    date: NaiveDate,
) -> Result<(Option<Decimal>, Option<Decimal>), String> {
    let row = table
        .split("\n  ---")
        .find(|row| row.contains(&format!("* {label}")))
        .ok_or_else(|| format!("Google 官方价格缺少 {label}，已保留原有价格。"))?;
    let cell = row
        .split("\n  * ")
        .nth(3)
        .ok_or("Google 付费价格格式已变化。")?;
    let values: Vec<_> = cell
        .lines()
        .map(str::trim)
        .filter(|line| line.starts_with('$'))
        .collect();
    let first = values.first().and_then(|value| dollar(value));
    if cell.contains("prompts > 200k") {
        return Ok((first, values.get(1).and_then(|value| dollar(value))));
    }
    for line in &values {
        if let Some((_, start)) = line.split_once(" starting ") {
            let start = NaiveDate::parse_from_str(start.trim_end_matches('.'), "%B %d, %Y")
                .map_err(|_| "Google 促销日期无法识别，已保留原有价格。")?;
            if date >= start {
                return Ok((dollar(line), None));
            }
        }
    }
    Ok((first, None))
}
