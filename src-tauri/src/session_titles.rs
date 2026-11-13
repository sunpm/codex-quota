// Title sources and the distinct-title query follow cc-switch (MIT).
// Copyright (c) 2025 Jason Young. See Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
use rusqlite::{Connection, OpenFlags};
use serde::Deserialize;
use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::{self, BufRead, BufReader},
    path::{Path, PathBuf},
};

#[derive(Deserialize)]
struct SessionIndexEntry {
    id: String,
    thread_name: String,
}

#[derive(Default, Deserialize)]
struct TitleConfig {
    sqlite_home: Option<String>,
}

pub fn read(codex_home: &Path) -> (BTreeMap<String, String>, Vec<String>) {
    let mut titles = BTreeMap::new();
    let mut warnings = Vec::new();
    if read_index(&codex_home.join("session_index.jsonl"), &mut titles).is_err() {
        warnings.push("会话标题索引无法读取，用量统计不受影响。".into());
    }
    let mut paths = vec![codex_home.join("state_5.sqlite")];
    match database_override(codex_home) {
        Ok(Some(directory)) => {
            let path = directory.join("state_5.sqlite");
            if !paths.contains(&path) {
                paths.push(path);
            }
        }
        Ok(None) => {}
        Err(()) => warnings.push("Codex 标题目录配置无法读取，暂使用默认目录。".into()),
    }
    for path in paths {
        if path.exists() && read_database(&path, &mut titles).is_err() {
            warnings.push("会话标题数据库无法读取，暂使用标题索引或项目名。".into());
        }
    }
    warnings.dedup();
    (titles, warnings)
}

fn read_index(path: &Path, titles: &mut BTreeMap<String, String>) -> io::Result<()> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    for line in BufReader::new(file).lines() {
        let line = line?;
        let Ok(entry) = serde_json::from_str::<SessionIndexEntry>(&line) else {
            continue;
        };
        let id = entry.id.trim();
        let title = entry.thread_name.trim();
        if !id.is_empty() && !title.is_empty() {
            titles.insert(id.to_owned(), title.chars().take(200).collect());
        }
    }
    Ok(())
}

fn database_override(codex_home: &Path) -> Result<Option<PathBuf>, ()> {
    let config = match fs::read_to_string(codex_home.join("config.toml")) {
        Ok(text) => toml::from_str::<TitleConfig>(&text).map_err(|_| ())?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => TitleConfig::default(),
        Err(_) => return Err(()),
    };
    let path = config
        .sqlite_home
        .filter(|path| !path.trim().is_empty())
        .or_else(|| std::env::var("CODEX_SQLITE_HOME").ok());
    let Some(path) = path
        .map(|path| path.trim().to_owned())
        .filter(|path| !path.is_empty())
    else {
        return Ok(None);
    };
    let resolved = if path == "~" {
        dirs::home_dir().ok_or(())?
    } else if let Some(rest) = path.strip_prefix("~/").or_else(|| path.strip_prefix("~\\")) {
        dirs::home_dir().ok_or(())?.join(rest)
    } else {
        PathBuf::from(path)
    };
    Ok(Some(resolved))
}

fn read_database(path: &Path, titles: &mut BTreeMap<String, String>) -> rusqlite::Result<()> {
    let connection = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
    // Some Codex titles duplicate the full first message; exclude those without loading message bodies.
    let mut statement = connection.prepare(
        "SELECT id, substr(trim(title), 1, 200) FROM threads WHERE trim(title) <> '' \
         AND (first_user_message IS NULL OR trim(title) <> trim(first_user_message))",
    )?;
    for row in statement.query_map([], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
    })? {
        let (id, title) = row?;
        titles.insert(id, title);
    }
    Ok(())
}
