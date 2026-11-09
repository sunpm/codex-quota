// Native field associations adapted from CC Switch and TokenUsageInsights (MIT).
// SQLite coverage and timestamp rules informed by CodexBar (MIT).
// See Resources/ThirdPartyNotices/antigravity-usage-NOTICE.txt.
use crate::{parse_timestamp, UsageRecord, UsageTokens};
use prost::Message;
use rusqlite::{Connection, OpenFlags};
use serde::Deserialize;
use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    fs::{self, File},
    io::{self, BufRead, BufReader},
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};

#[derive(Default, Clone)]
pub(crate) struct Scan {
    pub records: Vec<UsageRecord>,
    pub replaced_ids: Vec<String>,
    pub warnings: Vec<String>,
    pub file_count: usize,
}

#[derive(Clone, PartialEq)]
struct Stamp {
    size: u64,
    modified: SystemTime,
    identity: Option<file_id::FileId>,
}

fn stamp(path: &Path) -> io::Result<Option<Stamp>> {
    match fs::metadata(path) {
        Ok(metadata) => Ok(Some(Stamp {
            size: metadata.len(),
            modified: metadata.modified()?,
            identity: file_id::get_file_id(path).ok(),
        })),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

pub(crate) struct AntigravityUsageReader {
    roots: [PathBuf; 2],
    cache: HashMap<PathBuf, (Vec<Option<Stamp>>, Scan)>,
}

impl AntigravityUsageReader {
    pub fn new(home: PathBuf) -> Self {
        Self {
            roots: [home.join("antigravity-cli"), home.join("antigravity")],
            cache: HashMap::new(),
        }
    }

    pub fn clear_cache(&mut self) {
        self.cache.clear();
    }

    pub fn scan(&mut self, rescan: bool) -> Scan {
        if rescan {
            self.clear_cache();
        }
        let mut result = Scan::default();
        let mut candidates = Vec::new();
        let mut alive = BTreeSet::new();
        let mut unreadable = 0;
        for root in &self.roots {
            let mut sessions = BTreeSet::new();
            for directory in [root.join("brain"), root.join("conversations"), root.clone()] {
                let entries = match fs::read_dir(&directory) {
                    Ok(entries) => entries,
                    Err(error) if error.kind() == io::ErrorKind::NotFound => continue,
                    Err(_) => {
                        unreadable += 1;
                        continue;
                    }
                };
                for entry in entries {
                    let Ok(entry) = entry else {
                        unreadable += 1;
                        continue;
                    };
                    let path = entry.path();
                    let Ok(kind) = entry.file_type() else {
                        unreadable += 1;
                        continue;
                    };
                    if directory == root.join("brain") && kind.is_dir() {
                        sessions.insert(entry.file_name().to_string_lossy().into_owned());
                    } else if kind.is_file()
                        && path.extension().is_some_and(|ext| ext == "db")
                        && path
                            .file_name()
                            .is_none_or(|name| name != "conversation_summaries.db")
                    {
                        if let Some(id) = path
                            .file_stem()
                            .and_then(|v| v.to_str())
                            .filter(|id| crate::usage::is_uuid(id))
                        {
                            sessions.insert(id.into());
                        }
                    }
                }
            }
            for session in sessions {
                let transcript = root
                    .join("brain")
                    .join(&session)
                    .join(".system_generated/logs/transcript_full.jsonl");
                let nested_db = root.join("conversations").join(format!("{session}.db"));
                let database = if nested_db.exists() {
                    nested_db
                } else {
                    root.join(format!("{session}.db"))
                };
                let paths = [
                    transcript.clone(),
                    database.clone(),
                    PathBuf::from(format!("{}-wal", database.display())),
                ];
                let stamps = match paths
                    .iter()
                    .map(|p| stamp(p))
                    .collect::<io::Result<Vec<_>>>()
                {
                    Ok(stamps) => stamps,
                    Err(_) => {
                        unreadable += 1;
                        continue;
                    }
                };
                if stamps[0].is_none() && stamps[1].is_none() {
                    continue;
                }
                alive.insert(transcript.clone());
                let modified = stamps.iter().flatten().map(|s| s.modified).max().unwrap();
                let scan = if let Some((_, cached)) = self
                    .cache
                    .get(&transcript)
                    .filter(|(old, _)| old == &stamps)
                {
                    cached.clone()
                } else {
                    let scan = read_session(&session, &transcript, &database, &stamps);
                    // Re-read changed sessions in full: agy rewrites completed steps, not just appends.
                    if scan.warnings.is_empty() {
                        self.cache
                            .insert(transcript.clone(), (stamps, scan.clone()));
                    }
                    scan
                };
                candidates.push((modified, scan));
            }
        }
        self.cache.retain(|path, _| alive.contains(path));
        candidates.sort_by_key(|(modified, _)| *modified);
        let mut records: BTreeMap<String, UsageRecord> = BTreeMap::new();
        for (_, scan) in candidates {
            result.file_count += scan.file_count;
            result.warnings.extend(scan.warnings);
            result.replaced_ids.extend(scan.replaced_ids);
            for mut record in scan.records {
                if let Some(old) = records.get(&record.id) {
                    if old.tokens.complete()
                        && record.tokens.complete()
                        && old.tokens != record.tokens
                    {
                        result.warnings.push("Antigravity：同一步骤的副本计数不同，采用最近修改的来源；统计可能不完整。".into());
                    }
                    if record.model == "unknown" {
                        record.model = old.model.clone();
                    }
                    if record.project.is_empty() {
                        record.project = old.project.clone();
                    }
                    record.estimated_duration =
                        record.estimated_duration.or(old.estimated_duration);
                    record.estimated_first_token =
                        record.estimated_first_token.or(old.estimated_first_token);
                }
                records.insert(record.id.clone(), record);
            }
        }
        for id in &result.replaced_ids {
            records.remove(id);
        }
        result.records = records.into_values().collect();
        if unreadable > 0 {
            result.warnings.push(format!(
                "Antigravity：{unreadable} 处数据无法读取，统计不完整。"
            ));
        }
        result.warnings.sort();
        result.warnings.dedup();
        result
    }
}

#[derive(Deserialize)]
struct TranscriptRow {
    step_index: u64,
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    status: String,
    created_at: Option<String>,
    input_tokens: Option<u64>,
    output_tokens: Option<u64>,
    cache_read_tokens: Option<u64>,
    cache_write_tokens: Option<u64>,
    model: Option<String>,
    model_name: Option<String>,
    content: Option<String>,
}

fn known_model(value: &str) -> Option<String> {
    let value = value.trim();
    (!value.is_empty()
        && !["unknown", "none", "inherit", "flash", "pro"]
            .contains(&value.to_ascii_lowercase().as_str()))
    .then(|| value.to_owned())
}

fn read_session(
    session: &str,
    transcript: &Path,
    database: &Path,
    stamps: &[Option<Stamp>],
) -> Scan {
    let mut scan = Scan::default();
    let mut rows = BTreeMap::new();
    let mut invalid = 0;
    if stamps[0].is_some() {
        match File::open(transcript) {
            Ok(file) => {
                scan.file_count += 1;
                for line in BufReader::new(file).lines() {
                    let row = line
                        .ok()
                        .and_then(|line| serde_json::from_str::<TranscriptRow>(&line).ok());
                    match row {
                        Some(row) => {
                            rows.insert(row.step_index, row);
                        }
                        None => invalid += 1,
                    }
                }
            }
            Err(_) => scan
                .warnings
                .push("Antigravity：部分 JSONL 无法读取，统计不完整。".into()),
        }
    }
    let native = if stamps[1].is_some() {
        match read_database(database) {
            Ok(native) => {
                scan.file_count += 1;
                native
            }
            Err(_) => {
                scan.warnings.push("Antigravity：部分 SQLite 无法读取或格式不支持；保留可读取的日志，模型与历史覆盖可能不完整。".into());
                NativeSession::default()
            }
        }
    } else {
        NativeSession::default()
    };
    invalid += native.invalid;
    let mut selected_model = None;
    let mut records = native.records;
    for (step, row) in rows {
        if row.kind == "USER_INPUT" {
            if let Some(content) = row.content.as_deref() {
                if let Some((_, tail)) =
                    content.split_once("changed setting `Model Selection` from ")
                {
                    if let Some((_, name)) = tail.split_once(" to ") {
                        selected_model = known_model(
                            name.split(['\n', '`'])
                                .next()
                                .unwrap_or("")
                                .split(". ")
                                .next()
                                .unwrap_or("")
                                .trim_end_matches('.'),
                        );
                    }
                }
            }
            continue;
        }
        if row.kind != "PLANNER_RESPONSE" || row.status != "DONE" {
            continue;
        }
        let key = format!("s:{step}");
        let old = records.get(&key);
        let input = row.input_tokens.or_else(|| old.map(|r| r.tokens.input));
        let output = row.output_tokens.or_else(|| old.map(|r| r.tokens.output));
        let cached = row
            .cache_read_tokens
            .or_else(|| old.map(|r| r.tokens.cached));
        if input.is_none() && output.is_none() && cached.is_none() {
            invalid += 1;
            continue;
        }
        let tokens = UsageTokens {
            input: input.unwrap_or(0),
            output: output.unwrap_or(0),
            cached: cached.unwrap_or(0),
            cache_write: row.cache_write_tokens.unwrap_or(0),
            cache_write_reported: Some(row.cache_write_tokens.is_some()),
            input_reported: Some(input.is_some()),
            output_reported: Some(output.is_some()),
            cached_reported: Some(cached.is_some()),
            ..Default::default()
        };
        let date = row
            .created_at
            .as_deref()
            .and_then(parse_timestamp)
            .or_else(|| old.map(|r| r.date));
        let Some(date) = date.filter(|date| *date > 0.0) else {
            invalid += 1;
            continue;
        };
        if !tokens.valid_history() {
            invalid += 1;
            continue;
        }
        let model = row
            .model
            .as_deref()
            .and_then(known_model)
            .or_else(|| row.model_name.as_deref().and_then(known_model))
            .or_else(|| old.and_then(|r| known_model(&r.model)))
            .or_else(|| selected_model.clone())
            .unwrap_or_else(|| "unknown".into());
        let record = UsageRecord {
            id: key.clone(),
            service: "antigravity".into(),
            session: session.into(),
            project: native.project.clone(),
            model,
            date,
            tokens,
            service_tier: "unknown".into(),
            is_us_only: false,
            service_tier_reported: Some(false),
            estimated_duration: old.and_then(|r| r.estimated_duration),
            estimated_first_token: old.and_then(|r| r.estimated_first_token),
            cost: None,
        };
        records.insert(key, record);
    }
    let prefix = format!("antigravity:v2:{session}:");
    for (key, mut record) in records {
        record.id = format!("{prefix}{key}");
        record.session = session.into();
        record.project = native.project.clone();
        scan.records.push(record);
    }
    scan.replaced_ids = native
        .linked_generations
        .into_iter()
        .map(|index| format!("{prefix}g:{index}"))
        .collect();
    let missing = scan.records.iter().filter(|r| !r.tokens.complete()).count();
    if missing > 0 {
        scan.warnings.push(format!(
            "Antigravity：{missing} 条记录缺少部分 Token，汇总仅包含已知计数，费用未知。"
        ));
    }
    if invalid > 0 {
        scan.warnings.push(format!(
            "Antigravity：{invalid} 条记录缺少可靠时间或计数，或格式不支持，未导入；统计不完整。"
        ));
    }
    scan
}

// Decode only established fields; no schema generation or message-body storage.
#[derive(Clone, PartialEq, Message)]
struct Timestamp {
    #[prost(int64, tag = "1")]
    seconds: i64,
    #[prost(int32, tag = "2")]
    nanos: i32,
}
impl Timestamp {
    fn seconds(&self) -> Option<f64> {
        (self.seconds >= 0
            && self.seconds <= 253_402_300_799
            && (0..1_000_000_000).contains(&self.nanos))
        .then_some(self.seconds as f64 + self.nanos as f64 / 1e9)
    }
}
#[derive(Clone, PartialEq, Message)]
struct StepMetadata {
    #[prost(message, optional, tag = "1")]
    created: Option<Timestamp>,
    #[prost(message, optional, tag = "20")]
    generation: Option<GenerationReference>,
}
#[derive(Clone, PartialEq, Message)]
struct GenerationReference {
    #[prost(uint64, tag = "3")]
    index: u64,
}
#[derive(Clone, PartialEq, Message)]
struct Generation {
    #[prost(message, optional, tag = "1")]
    response: Option<Response>,
}
#[derive(Clone, PartialEq, Message)]
struct Response {
    #[prost(message, optional, tag = "4")]
    tokens: Option<NativeTokens>,
    #[prost(message, optional, tag = "9")]
    timing: Option<GenerationTime>,
    #[prost(message, optional, tag = "11")]
    first: Option<Timestamp>,
    #[prost(message, optional, tag = "12")]
    streaming: Option<Timestamp>,
    #[prost(string, tag = "19")]
    model: String,
}
#[derive(Clone, PartialEq, Message)]
struct GenerationTime {
    #[prost(message, optional, tag = "4")]
    created: Option<Timestamp>,
}
#[derive(Clone, PartialEq, Message)]
struct NativeTokens {
    #[prost(uint64, tag = "2")]
    input: u64,
    #[prost(uint64, tag = "3")]
    output: u64,
    #[prost(uint64, tag = "5")]
    cached: u64,
}
#[derive(Clone, PartialEq, Message)]
struct Trajectory {
    #[prost(message, repeated, tag = "1")]
    workspaces: Vec<Workspace>,
    #[prost(string, repeated, tag = "7")]
    workspace_uris: Vec<String>,
}
#[derive(Clone, PartialEq, Message)]
struct Workspace {
    #[prost(string, tag = "1")]
    uri: String,
}

#[derive(Default)]
struct NativeSession {
    records: BTreeMap<String, UsageRecord>,
    linked_generations: BTreeSet<u64>,
    project: String,
    invalid: usize,
}

fn read_database(path: &Path) -> Result<NativeSession, Box<dyn std::error::Error>> {
    let wal = PathBuf::from(format!("{}-wal", path.display()));
    let before = stamp(path)?;
    // Closed WAL databases have no sidecars. Immutable avoids creating them; a live WAL
    // always uses SQLite's read transaction so committed generations remain visible.
    let idle = stamp(&wal)?.is_none();
    let mut uri = url::Url::from_file_path(path).map_err(|_| "invalid database path")?;
    uri.set_query(Some(if idle {
        "mode=ro&immutable=1"
    } else {
        "mode=ro"
    }));
    let mut conn = Connection::open_with_flags(
        uri.as_str(),
        OpenFlags::SQLITE_OPEN_READ_ONLY
            | OpenFlags::SQLITE_OPEN_URI
            | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    conn.busy_timeout(Duration::ZERO)?;
    let tx = conn.transaction()?;
    let mut result = NativeSession::default();
    let mut steps: BTreeMap<u64, (u64, Option<f64>)> = BTreeMap::new();
    let has_steps: bool = tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='steps')",
        [],
        |row| row.get(0),
    )?;
    if has_steps {
        let mut query = tx.prepare("SELECT idx,status,metadata FROM steps WHERE step_type=15")?;
        let entries = query.query_map([], |row| {
            Ok((
                row.get::<_, i64>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, Vec<u8>>(2)?,
            ))
        })?;
        for entry in entries {
            let (step, status, bytes) = entry?;
            let Ok(step) = u64::try_from(step) else {
                result.invalid += 1;
                continue;
            };
            let Ok(metadata) = StepMetadata::decode(bytes.as_slice()) else {
                result.invalid += 1;
                continue;
            };
            if let Some(reference) = metadata.generation {
                result.linked_generations.insert(reference.index);
                if status == 3 {
                    steps.insert(
                        reference.index,
                        (step, metadata.created.and_then(|t| t.seconds())),
                    );
                }
            }
        }
    }
    let mut query = tx.prepare("SELECT idx,data FROM gen_metadata")?;
    let entries = query.query_map([], |row| {
        Ok((row.get::<_, i64>(0)?, row.get::<_, Vec<u8>>(1)?))
    })?;
    for entry in entries {
        let (index, bytes) = entry?;
        let Ok(index) = u64::try_from(index) else {
            result.invalid += 1;
            continue;
        };
        let Ok(generation) = Generation::decode(bytes.as_slice()) else {
            result.invalid += 1;
            continue;
        };
        let Some(response) = generation.response else {
            continue;
        };
        let Some(tokens) = response.tokens else {
            result.invalid += 1;
            continue;
        };
        if result.linked_generations.contains(&index) && !steps.contains_key(&index) {
            continue;
        }
        let step = steps.get(&index);
        let date = step.and_then(|(_, date)| *date).or_else(|| {
            response
                .timing
                .and_then(|t| t.created)
                .and_then(|t| t.seconds())
        });
        let Some(date) = date.filter(|t| *t > 0.0) else {
            result.invalid += 1;
            continue;
        };
        // Both JSONL and native field 2 are fresh input; field 3 already includes thinking.
        // Scalar fields omitted from this protobuf token message are its defined zero values.
        let tokens = UsageTokens {
            input: tokens.input,
            output: tokens.output,
            cached: tokens.cached,
            input_reported: Some(true),
            output_reported: Some(true),
            cached_reported: Some(true),
            cache_write_reported: Some(false),
            ..Default::default()
        };
        if !tokens.valid_history() {
            result.invalid += 1;
            continue;
        }
        let first = response.first.and_then(|t| t.seconds());
        let duration = first
            .zip(response.streaming.and_then(|t| t.seconds()))
            .map(|(a, b)| a + b)
            .filter(|v| *v > 0.0);
        let key = step.map_or_else(|| format!("g:{index}"), |(step, _)| format!("s:{step}"));
        result.records.insert(
            key.clone(),
            UsageRecord {
                id: key,
                service: "antigravity".into(),
                session: String::new(),
                project: String::new(),
                model: known_model(&response.model).unwrap_or_else(|| "unknown".into()),
                date,
                tokens,
                service_tier: "unknown".into(),
                service_tier_reported: Some(false),
                is_us_only: false,
                estimated_duration: duration,
                estimated_first_token: first,
                cost: None,
            },
        );
    }
    let has_project: bool = tx.query_row("SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='table' AND name='trajectory_metadata_blob')", [], |row| row.get(0))?;
    if has_project {
        let mut projects = BTreeSet::new();
        let mut query = tx.prepare("SELECT data FROM trajectory_metadata_blob")?;
        for bytes in query.query_map([], |row| row.get::<_, Vec<u8>>(0))? {
            if let Ok(trajectory) = Trajectory::decode(bytes?.as_slice()) {
                let uris = if trajectory.workspace_uris.is_empty() {
                    trajectory.workspaces.into_iter().map(|w| w.uri).collect()
                } else {
                    trajectory.workspace_uris
                };
                for uri in uris {
                    if let Some(path) = url::Url::parse(&uri)
                        .ok()
                        .and_then(|u| u.to_file_path().ok())
                    {
                        projects.insert(path.to_string_lossy().into_owned());
                    }
                }
            }
        }
        if projects.len() == 1 {
            result.project = projects.into_iter().next().unwrap();
        }
    }
    if idle && (stamp(&wal)?.is_some() || stamp(path)? != before) {
        return Err("database changed during read".into());
    }
    Ok(result)
}
