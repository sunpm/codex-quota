use std::{collections::BTreeMap, env, fs, time::Duration};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<_> = env::args().collect();
    if args.len() != 3 {
        return Err("usage: update-prices <YYYY-MM-DD> <output-json>".into());
    }
    let date = chrono::NaiveDate::parse_from_str(&args[1], "%Y-%m-%d")?;
    let http = reqwest::Client::builder()
        .timeout(Duration::from_secs(25))
        .user_agent("CodexQuota")
        .build()?;
    let mut prices = BTreeMap::new();
    for (provider, url) in quota_core::OFFICIAL_PRICE_SOURCES {
        let text = http
            .get(url)
            .header(reqwest::header::ACCEPT, "text/markdown")
            .send()
            .await?
            .error_for_status()?
            .text()
            .await?;
        let decoded = quota_core::decode_official_prices(provider, &text, date)?;
        eprintln!("{provider}: {} service/model prices", decoded.len());
        prices.extend(decoded);
    }
    fs::write(
        &args[2],
        format!("{}\n", serde_json::to_string_pretty(&prices)?),
    )?;
    Ok(())
}
