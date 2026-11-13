// Log formats and deduplication adapted from nanvon/cc-bar (MIT).
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
use crate::{parse_timestamp, project::main_project_path, write_json_atomic, SWIFT_EPOCH_OFFSET};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    fs::{self, File},
    io::{self, BufRead, BufReader, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
    time::SystemTime,
};

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct UsageTokens {
    pub input: u64,
    pub output: u64,
    pub cached: u64,
    pub cache_write: u64,
    #[serde(default)]
    pub cache_write_long: u64,
    pub cache_write_reported: Option<bool>,
    pub input_reported: Option<bool>,
    pub output_reported: Option<bool>,
    pub cached_reported: Option<bool>,
}

impl UsageTokens {
    pub fn complete(&self) -> bool {
        self.input_reported != Some(false)
            && self.output_reported != Some(false)
            && self.cached_reported != Some(false)
    }
    pub fn total(&self) -> u64 {
        self.input + self.output + self.cached + self.cache_write
    }
    pub fn cache_hit_rate(&self) -> Option<f64> {
        let incoming = self.input + self.cached + self.cache_write;
        (incoming > 0).then(|| self.cached as f64 / incoming as f64)
    }
    pub fn reported_cache_write(&self) -> Option<u64> {
        (self.cache_write_reported == Some(true) || self.cache_write > 0)
            .then_some(self.cache_write)
    }
    pub(crate) fn valid_history(&self) -> bool {
        [self.input, self.output, self.cached, self.cache_write]
            .iter()
            .all(|n| *n < i64::MAX as u64 / 16)
            && self.cache_write_long <= self.cache_write
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct UsageRecord {
    pub id: String,
    pub service: String,
    pub session: String,
    pub project: String,
    pub model: String,
    pub date: f64,
    pub tokens: UsageTokens,
    pub service_tier: String,
    #[serde(rename = "isUSOnly")]
    pub is_us_only: bool,
    pub service_tier_reported: Option<bool>,
    pub estimated_duration: Option<f64>,
    pub estimated_first_token: Option<f64>,
    #[serde(default)]
    pub cost: Option<String>,
}

impl UsageRecord {
    pub fn same_usage(&self, other: &Self) -> bool {
        self.id == other.id
            && self.service == other.service
            && self.session == other.session
            && self.project == other.project
            && self.model == other.model
            && self.date == other.date
            && self.tokens == other.tokens
            && self.service_tier == other.service_tier
            && self.is_us_only == other.is_us_only
            && self.service_tier_reported == other.service_tier_reported
            && self.estimated_duration == other.estimated_duration
            && self.estimated_first_token == other.estimated_first_token
    }

    pub fn estimated_output_tokens_per_second(&self) -> Option<f64> {
        self.estimated_duration
            .filter(|duration| self.tokens.output >= 200 && *duration >= 1.0)
            .map(|duration| self.tokens.output as f64 / duration)
    }
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageScan {
    pub records: Vec<UsageRecord>,
    pub project_roots: BTreeMap<String, String>,
    pub warnings: Vec<String>,
    pub history_error: Option<String>,
    pub file_count: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
struct UsageHistory {
    version: u32,
    records: BTreeMap<String, Value>,
    #[serde(default)]
    project_roots: BTreeMap<String, String>,
    // 未接入服务的旧记录及其他元数据保持原值，不参与展示。
    #[serde(flatten)]
    extra: BTreeMap<String, Value>,
}

impl Default for UsageHistory {
    fn default() -> Self {
        Self {
            version: 1,
            records: BTreeMap::new(),
            project_roots: BTreeMap::new(),
            extra: BTreeMap::new(),
        }
    }
}

impl UsageHistory {
    fn load(path: &Path) -> Result<Self, String> {
        let file = match File::open(path) {
            Ok(file) => file,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Self::default()),
            Err(_) => return Err("已保存历史无法读取，原文件已保留；当前仅显示现存日志。".into()),
        };
        let history: Self = serde_json::from_reader(BufReader::new(file))
            .map_err(|_| "已保存历史无法读取，原文件已保留；当前仅显示现存日志。")?;
        if history.version != 1 {
            return Err("历史版本暂不兼容，原文件已保留；当前仅显示现存日志。".into());
        }
        Ok(history)
    }
    fn supported_records(&self) -> Result<BTreeMap<String, UsageRecord>, String> {
        let mut records = BTreeMap::new();
        for (key, value) in &self.records {
            let service = value.get("service").and_then(Value::as_str);
            if service != Some("codex")
                && !(service == Some("antigravity") && key.starts_with("antigravity:v2:"))
            {
                continue;
            }
            let mut record: UsageRecord = serde_json::from_value(value.clone())
                .map_err(|_| "已保存历史无法读取，原文件已保留；当前仅显示现存日志。")?;
            if !record.tokens.valid_history() {
                return Err("已保存历史包含无效用量，原文件已保留。".into());
            }
            record.date += SWIFT_EPOCH_OFFSET;
            record.cost = None;
            records.insert(key.clone(), record);
        }
        Ok(records)
    }
    fn merge_records(&mut self, records: &BTreeMap<String, UsageRecord>) {
        for (id, record) in records {
            let mut persisted = record.clone();
            persisted.date -= SWIFT_EPOCH_OFFSET;
            persisted.cost = None;
            let mut value = serde_json::to_value(persisted).expect("typed usage record");
            value.as_object_mut().expect("usage object").remove("cost");
            self.records.insert(id.clone(), value);
        }
    }
}

#[derive(Clone)]
struct CachedFile {
    size: u64,
    modified: SystemTime,
    identifier: Option<file_id::FileId>,
    records: Vec<UsageRecord>,
    invalid_lines: usize,
    continuation: Option<(String, String)>,
    offset: u64,
    complete_record_count: usize,
    complete_invalid_lines: usize,
    context: ParseContext,
}

#[derive(Clone)]
struct ParseContext {
    session: String,
    continuation: Option<(String, String)>,
    emitter: String,
    project: String,
    model: String,
    saw_meta: bool,
    service_tier: String,
    service_tier_reported: bool,
    timer: RequestTimer,
    previous_signature: Option<String>,
    line_number: usize,
}

pub struct LocalUsageReader {
    codex_home: PathBuf,
    history_path: PathBuf,
    cache: HashMap<PathBuf, CachedFile>,
    history: UsageHistory,
    saved_history: UsageHistory,
    history_loaded: bool,
    records: BTreeMap<String, UsageRecord>,
    antigravity: crate::antigravity_usage::AntigravityUsageReader,
}

impl LocalUsageReader {
    pub fn new(codex_home: PathBuf, gemini_home: PathBuf, history_path: PathBuf) -> Self {
        Self {
            codex_home,
            history_path,
            cache: HashMap::new(),
            history: UsageHistory::default(),
            saved_history: UsageHistory::default(),
            history_loaded: false,
            records: BTreeMap::new(),
            antigravity: crate::antigravity_usage::AntigravityUsageReader::new(gemini_home),
        }
    }
    pub fn clear_history(&mut self, service: &str) -> Result<(), String> {
        if !["codex", "antigravity"].contains(&service) {
            return Err("请选择要清除历史的服务。".into());
        }
        let mut history = UsageHistory::load(&self.history_path)?;
        let mut retained = history.supported_records()?;
        retained.retain(|_, record| record.service != service);
        history
            .records
            .retain(|_, value| value.get("service").and_then(Value::as_str) != Some(service));
        let projects: BTreeSet<_> = history
            .records
            .values()
            .filter_map(|value| value.get("project").and_then(Value::as_str))
            .collect();
        history
            .project_roots
            .retain(|project, _| projects.contains(project.as_str()));
        if history.records.is_empty() {
            match fs::remove_file(&self.history_path) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::NotFound => {}
                Err(_) => return Err("无法清除已保存历史。".into()),
            }
            history = UsageHistory::default();
        } else {
            write_json_atomic(&self.history_path, &history)?;
        }
        self.history = history.clone();
        self.saved_history = history;
        self.history_loaded = true;
        self.records.retain(|_, record| record.service != service);
        for (id, record) in retained { self.records.entry(id).or_insert(record); }
        if service == "codex" { self.cache.clear(); }
        else { self.antigravity.clear_cache(); }
        Ok(())
    }
    pub fn scan(&mut self, rescan: bool) -> UsageScan {
        if rescan {
            self.cache.clear();
        }
        let mut result = UsageScan::default();
        if !self.history_loaded {
            match UsageHistory::load(&self.history_path)
                .and_then(|history| history.supported_records().map(|records| (history, records)))
            {
                Ok((history, records)) => {
                    self.history = history.clone();
                    self.saved_history = history;
                    self.history_loaded = true;
                    self.records = records;
                }
                Err(error) => {
                    result.history_error = Some(error);
                    self.records.clear();
                }
            }
        }
        let mut records = std::mem::take(&mut self.records);
        let mut files = Vec::new();
        let mut failures = 0;
        for name in ["sessions", "archived_sessions"] {
            let root = self.codex_home.join(name);
            if root.exists() {
                collect_files(&root, &mut files, &mut failures);
            }
        }
        // 父会话优先，fork 重放不把已发生用量挪到未来。
        files.sort_by(|a, b| a.file_name().cmp(&b.file_name()).then_with(|| a.cmp(b)));
        let alive: BTreeSet<_> = files.iter().cloned().collect();
        let mut invalid = 0;
        let mut continuations = BTreeMap::new();
        for file in files {
            let parsed = self.read_file(&file);
            let saved = match parsed {
                Ok(saved) => {
                    if let Some(saved) = saved {
                        self.cache.insert(file.clone(), saved);
                    }
                    result.file_count += 1;
                    self.cache.get(&file)
                }
                Err(_) => {
                    failures += 1;
                    self.cache.get(&file)
                }
            };
            if let Some(saved) = saved {
                invalid += saved.invalid_lines;
                if let Some((segment, thread)) = &saved.continuation {
                    continuations.insert(segment.clone(), thread.clone());
                }
                for record in &saved.records {
                    merge_record(&mut records, record);
                }
            }
        }
        self.cache.retain(|file, _| alive.contains(file));
        for record in records.values_mut() {
            if let Some(thread) = continuations.get(&record.session).filter(|_| record.service == "codex") {
                record.session = thread.clone();
            }
        }
        let antigravity = self.antigravity.scan(rescan);
        result.file_count += antigravity.file_count;
        result.warnings.extend(antigravity.warnings);
        for id in antigravity.replaced_ids {
            records.remove(&id);
            self.history.records.remove(&id);
        }
        for mut record in antigravity.records {
            if let Some(old) = records.get(&record.id) {
                if record.model == "unknown" { record.model = old.model.clone(); }
                if record.project.is_empty() { record.project = old.project.clone(); }
                record.estimated_duration = record.estimated_duration.or(old.estimated_duration);
                record.estimated_first_token = record.estimated_first_token.or(old.estimated_first_token);
            }
            records.insert(record.id.clone(), record);
        }
        let projects: BTreeSet<_> = records
            .values()
            .map(|record| record.project.clone())
            .collect();
        for project in projects {
            if let Some(root) = main_project_path(&project)
                .or_else(|| self.history.project_roots.get(&project).cloned())
            {
                result.project_roots.insert(project, root);
            }
        }
        if self.history_loaded {
            self.history.merge_records(&records);
            self.history
                .project_roots
                .extend(result.project_roots.clone());
            if self.history != self.saved_history {
                match write_json_atomic(&self.history_path, &self.history) {
                    Ok(()) => self.saved_history = self.history.clone(),
                    Err(_) => {
                        result.history_error =
                            Some("历史保存失败，新增用量暂仅保留在内存；下次刷新会重试。".into())
                    }
                }
            }
        }
        result.records = records.values().cloned().collect();
        self.records = records;
        result
            .records
            .sort_by(|a, b| a.date.total_cmp(&b.date).then_with(|| a.id.cmp(&b.id)));
        if failures > 0 {
            result
                .warnings
                .push(format!("Codex：{failures} 处日志无法读取，统计可能不完整"));
        }
        if invalid > 0 {
            result
                .warnings
                .push(format!("Codex：{invalid} 条记录格式无效，已跳过"));
        }
        result
    }
    pub fn invalidate_service(&mut self, service: &str) -> Result<(), String> {
        match service {
            "codex" => self.cache.clear(),
            "antigravity" => self.antigravity.clear_cache(),
            _ => return Err("请选择要重新扫描的服务。".into()),
        }
        Ok(())
    }
    fn read_file(&self, path: &Path) -> io::Result<Option<CachedFile>> {
        let metadata = fs::metadata(path)?;
        if !metadata.is_file() {
            return Err(io::Error::other("not regular file"));
        }
        let modified = metadata.modified()?;
        let identifier = file_id::get_file_id(path).ok();
        let previous = self.cache.get(path);
        if previous.is_some_and(|p| {
            p.identifier == identifier && p.size == metadata.len() && p.modified == modified
        }) {
            return Ok(None);
        }
        let appended = path.extension().is_some_and(|ext| ext == "jsonl")
            && identifier.is_some()
            && previous.is_some_and(|p| {
                p.identifier == identifier && metadata.len() > p.size && modified >= p.modified
            });
        parse_file(
            path,
            metadata.len(),
            modified,
            identifier,
            if appended { previous } else { None },
        )
        .map(Some)
    }
}

fn collect_files(directory: &Path, files: &mut Vec<PathBuf>, failures: &mut usize) {
    let entries = match fs::read_dir(directory) {
        Ok(entries) => entries,
        Err(_) => {
            *failures += 1;
            return;
        }
    };
    for entry in entries {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => {
                *failures += 1;
                continue;
            }
        };
        let name = entry.file_name();
        if name.to_string_lossy().starts_with('.') {
            continue;
        }
        match entry.file_type() {
            Ok(kind) if kind.is_dir() => collect_files(&entry.path(), files, failures),
            Ok(kind)
                if kind.is_file()
                    && (name.to_string_lossy().ends_with(".jsonl")
                        || name.to_string_lossy().ends_with(".jsonl.zst")) =>
            {
                files.push(entry.path())
            }
            Err(_) => *failures += 1,
            _ => {}
        }
    }
}

fn merge_record(records: &mut BTreeMap<String, UsageRecord>, record: &UsageRecord) {
    if let Some(old) = records.get_mut(&record.id) {
        if record.date > old.date {
            return;
        }
        if record.date == old.date {
            if [
                old.tokens.input,
                old.tokens.output,
                old.tokens.cached,
                old.tokens.cache_write,
                old.tokens.cache_write_long,
            ] != [
                record.tokens.input,
                record.tokens.output,
                record.tokens.cached,
                record.tokens.cache_write,
                record.tokens.cache_write_long,
            ] {
                return;
            }
            old.estimated_duration = old.estimated_duration.or(record.estimated_duration);
            old.estimated_first_token = old.estimated_first_token.or(record.estimated_first_token);
            old.service_tier_reported = old.service_tier_reported.or(record.service_tier_reported);
            old.tokens.cache_write_reported = old
                .tokens
                .cache_write_reported
                .or(record.tokens.cache_write_reported);
            return;
        }
    }
    records.insert(record.id.clone(), record.clone());
}

pub(crate) fn is_uuid(value: &str) -> bool {
    value.len() == 36
        && value.bytes().enumerate().all(|(i, byte)| {
            if [8, 13, 18, 23].contains(&i) {
                byte == b'-'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
}

fn parse_file(
    path: &Path,
    size: u64,
    modified: SystemTime,
    identifier: Option<file_id::FileId>,
    previous: Option<&CachedFile>,
) -> io::Result<CachedFile> {
    let compressed = path.extension().is_some_and(|ext| ext == "zst");
    let filename = path.file_name().unwrap_or_default().to_string_lossy();
    let filename = filename.strip_suffix(".zst").unwrap_or(&filename);
    let filename = filename.strip_suffix(".jsonl").unwrap_or(filename);
    let filename_id = filename
        .get(filename.len().saturating_sub(36)..)
        .unwrap_or(filename);
    let valid_uuid = is_uuid(filename_id);
    let session = if valid_uuid { filename_id } else { filename }.to_owned();
    let mut context = previous
        .map(|p| p.context.clone())
        .unwrap_or_else(|| ParseContext {
            emitter: session.clone(),
            session,
            continuation: None,
            project: String::new(),
            model: "未知模型".into(),
            saw_meta: false,
            service_tier: "standard".into(),
            service_tier_reported: false,
            timer: RequestTimer::default(),
            previous_signature: None,
            line_number: 0,
        });
    let mut records = previous
        .map(|p| p.records[..p.complete_record_count].to_vec())
        .unwrap_or_default();
    let mut invalid = previous.map_or(0, |p| p.complete_invalid_lines);
    let mut offset = previous.map_or(0, |p| p.offset);
    let mut file = File::open(path)?;
    let input: Box<dyn Read> = if compressed {
        // 默认读取全部拼接帧；解码器的 EOF 校验保留截断/损坏错误。
        Box::new(zstd::stream::read::Decoder::new(file)?)
    } else {
        file.seek(SeekFrom::Start(offset))?;
        Box::new(file.take(size.saturating_sub(offset)))
    };
    let mut reader = BufReader::with_capacity(256 * 1024, input);
    let mut line = Vec::new();
    let mut pending = Vec::new();
    loop {
        line.clear();
        let count = reader.read_until(b'\n', &mut line)?;
        if count == 0 {
            break;
        }
        if line.last() == Some(&b'\n') {
            offset += count as u64;
            line.pop();
            context.consume(
                &line,
                filename,
                filename_id,
                valid_uuid,
                &mut records,
                &mut invalid,
            );
        } else {
            pending = line;
            break;
        }
    }
    let checkpoint = context.clone();
    let complete_record_count = records.len();
    let complete_invalid_lines = invalid;
    // 无换行但完整的 JSON 参与展示；续读回到末行起点恢复上下文。
    if !pending.is_empty() && (compressed || serde_json::from_slice::<Value>(&pending).is_ok()) {
        context.consume(
            &pending,
            filename,
            filename_id,
            valid_uuid,
            &mut records,
            &mut invalid,
        );
    }
    Ok(CachedFile {
        size,
        modified,
        identifier,
        records,
        invalid_lines: invalid,
        continuation: context.continuation,
        offset,
        complete_record_count,
        complete_invalid_lines,
        context: checkpoint,
    })
}

impl ParseContext {
    fn consume(
        &mut self,
        line: &[u8],
        filename: &str,
        filename_id: &str,
        valid_uuid: bool,
        records: &mut Vec<UsageRecord>,
        invalid: &mut usize,
    ) {
        self.line_number += 1;
        if line.is_empty() {
            return;
        }
        let row: Map<String, Value> = match serde_json::from_slice(line) {
            Ok(row) => row,
            Err(_) => {
                *invalid += 1;
                return;
            }
        };
        let kind = row.get("type").and_then(Value::as_str).unwrap_or("");
        let empty = Map::new();
        let payload = row
            .get("payload")
            .and_then(Value::as_object)
            .unwrap_or(&empty);
        let date = row
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(parse_timestamp);
        if kind == "session_meta" {
            if let Some(id) = payload
                .get("id")
                .and_then(Value::as_str)
                .or_else(|| payload.get("session_id").and_then(Value::as_str))
            {
                self.emitter = id.into();
            }
            if !self.saw_meta {
                self.project = payload
                    .get("cwd")
                    .and_then(Value::as_str)
                    .unwrap_or("")
                    .into();
                if !valid_uuid {
                    self.session = self.emitter.clone();
                }
                let prefix = filename
                    .get(..filename.len().saturating_sub(37))
                    .unwrap_or("");
                let thread = prefix.get(prefix.len().saturating_sub(36)..).unwrap_or("");
                if filename.as_bytes().get(filename.len().saturating_sub(37)) == Some(&b'_')
                    && valid_uuid
                    && is_uuid(thread)
                    && thread == self.emitter
                {
                    self.continuation = Some((filename_id.into(), thread.into()));
                }
                self.saw_meta = true;
            }
            return;
        }
        if kind == "turn_context" {
            if let Some(model) = payload.get("model").and_then(Value::as_str) {
                self.model = model.into();
            }
            if let Some(tier) = payload.get("service_tier").and_then(Value::as_str) {
                self.service_tier = tier.into();
                self.service_tier_reported = true;
            }
            if let Some(date) = date {
                self.timer.boundary = Some(self.timer.boundary.unwrap_or(date).max(date));
            }
            return;
        }
        let event = payload.get("type").and_then(Value::as_str).unwrap_or("");
        if kind == "event_msg" && event == "thread_settings_applied" {
            let settings = payload
                .get("thread_settings")
                .and_then(Value::as_object)
                .unwrap_or(payload);
            if let Some(model) = settings.get("model").and_then(Value::as_str) {
                self.model = model.into();
            }
            let tier = settings.get("service_tier").and_then(Value::as_str);
            self.service_tier = tier.unwrap_or("unknown").into();
            self.service_tier_reported = tier.is_some();
            return;
        }
        if let Some(date) = date {
            if kind == "response_item" {
                if event == "message"
                    && payload.get("role").and_then(Value::as_str) != Some("assistant")
                {
                    self.timer.boundary = Some(self.timer.boundary.unwrap_or(date).max(date));
                } else if event.ends_with("_output") {
                    self.timer.boundary = Some(self.timer.boundary.unwrap_or(date).max(date));
                    if self.timer.last_output.is_some() {
                        self.timer.tool_output_after_model = Some(date);
                    }
                } else if event == "message" || event == "reasoning" || event.ends_with("_call") {
                    self.timer.observe_output(date, event.ends_with("_call"));
                }
            } else if kind == "token_usage_record" {
                if let Some(tokens) = payload
                    .get("usage")
                    .and_then(Value::as_object)
                    .and_then(token_counts)
                {
                    self.timer.usage_record = Some((date, tokens));
                }
            } else if kind == "event_msg" {
                match event {
                    "task_started" | "turn_aborted" => self.timer.reset(Some(date)),
                    "item_completed" => {
                        let item = payload
                            .get("item")
                            .and_then(|v| v.get("type"))
                            .and_then(Value::as_str);
                        if matches!(item, Some("Reasoning" | "AgentMessage")) {
                            if let Some(stamp) = payload
                                .get("started_at_ms")
                                .and_then(Value::as_f64)
                                .filter(|v| *v > 0.0 && *v <= date * 1000.0)
                            {
                                let started = stamp / 1000.0;
                                self.timer.first_output =
                                    Some(self.timer.first_output.unwrap_or(started).min(started));
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        if kind != "event_msg" || event != "token_count" {
            return;
        }
        let Some(info) = payload.get("info").and_then(Value::as_object) else {
            return;
        };
        let Some(usage) = info.get("last_token_usage").and_then(Value::as_object) else {
            return;
        };
        let signature = info
            .get("total_token_usage")
            .filter(|v| v.is_object())
            .map(canonical_signature);
        if signature.is_some() && signature == self.previous_signature {
            return;
        }
        self.previous_signature = signature.clone();
        let Some(tokens) = token_counts(usage) else {
            *invalid += 1;
            return;
        };
        let timing = self.timer.finish(date, &tokens);
        if tokens.total() == 0 {
            return;
        }
        let Some(date) = date else {
            *invalid += 1;
            return;
        };
        let signature =
            signature.unwrap_or_else(|| format!("{}:{}", self.session, self.line_number));
        records.push(UsageRecord {
            id: format!("codex:{}:{signature}", self.emitter),
            service: "codex".into(),
            session: self.session.clone(),
            project: self.project.clone(),
            model: self.model.clone(),
            date,
            tokens,
            service_tier: self.service_tier.to_lowercase(),
            is_us_only: false,
            service_tier_reported: Some(self.service_tier_reported),
            estimated_duration: timing.map(|value| value.0),
            estimated_first_token: timing.and_then(|value| value.1),
            cost: None,
        });
    }
}

fn canonical_signature(value: &Value) -> String {
    fn sorted(value: &Value) -> Value {
        match value {
            Value::Object(map) => Value::Object(
                map.iter()
                    .map(|(key, value)| (key.clone(), sorted(value)))
                    .collect::<BTreeMap<_, _>>()
                    .into_iter()
                    .collect(),
            ),
            Value::Array(values) => Value::Array(values.iter().map(sorted).collect()),
            _ => value.clone(),
        }
    }
    serde_json::to_string(&sorted(value)).expect("JSON signature")
}

fn token_counts(values: &Map<String, Value>) -> Option<UsageTokens> {
    let count = |value: Option<&Value>| {
        value
            .and_then(|v| {
                v.as_u64().or_else(|| {
                    v.as_f64()
                        .filter(|n| *n >= 0.0 && n.fract() == 0.0 && *n < (i64::MAX / 16) as f64)
                        .map(|n| n as u64)
                })
            })
            .filter(|n| *n < i64::MAX as u64 / 16)
    };
    let input = count(values.get("input_tokens"))?;
    let output = count(values.get("output_tokens"))?;
    let details = values.get("input_tokens_details");
    let cached = count(values.get("cached_input_tokens"))
        .or_else(|| count(values.get("cache_read_input_tokens")))
        .or_else(|| count(details.and_then(|v| v.get("cached_tokens"))))
        .unwrap_or(0);
    let mut write = count(values.get("cache_write_input_tokens"))
        .or_else(|| count(values.get("cache_write_tokens")))
        .or_else(|| count(details.and_then(|v| v.get("cache_write_tokens"))));
    let mut cache_write_long = 0;
    if let Some(ttl) = details.and_then(|v| v.get("cache_write_tokens_details")) {
        let short = count(ttl.get("ttl_30m_tokens"))?;
        cache_write_long = count(ttl.get("ttl_12h_tokens"))?;
        let total = short + cache_write_long;
        if write.is_some_and(|count| count != total) { return None; }
        write = Some(total);
    }
    let cache_write = write.unwrap_or(0);
    if cached + cache_write > input {
        return None;
    }
    Some(UsageTokens {
        input: input - cached - cache_write,
        output,
        cached,
        cache_write,
        cache_write_long,
        cache_write_reported: Some(write.is_some()),
        ..Default::default()
    })
}

// Timing boundaries adapted from farion1231/cc-switch (MIT).
// Copyright (c) 2025 Jason Young. See Resources/ThirdPartyNotices/cc-switch-LICENSE.txt.
#[derive(Clone, Default)]
struct RequestTimer {
    boundary: Option<f64>,
    last_token_count: Option<f64>,
    start: Option<f64>,
    last_output: Option<f64>,
    tool_output_after_model: Option<f64>,
    usage_record: Option<(f64, UsageTokens)>,
    first_output: Option<f64>,
    starts_with_tool_call: bool,
}

impl RequestTimer {
    fn observe_output(&mut self, date: f64, is_tool_call: bool) {
        if self.start.is_none() && self.last_token_count.is_some_and(|last| date - last <= 0.1) {
            return;
        }
        if self.last_output.is_none() {
            self.start = self.boundary;
            self.starts_with_tool_call = is_tool_call;
        }
        self.last_output = Some(date);
        self.tool_output_after_model = None;
    }
    fn reset(&mut self, date: Option<f64>) {
        *self = Self {
            boundary: self.boundary.into_iter().chain(date).max_by(f64::total_cmp),
            last_token_count: self.last_token_count,
            ..Self::default()
        };
    }
    fn finish(&mut self, date: Option<f64>, tokens: &UsageTokens) -> Option<(f64, Option<f64>)> {
        let timing = self.start.or(self.boundary).and_then(|start| {
            let end = if let Some((stamp, record)) = &self.usage_record {
                if record.input + record.cache_write == tokens.input + tokens.cache_write
                    && record.cached == tokens.cached
                    && record.output == tokens.output
                {
                    Some(*stamp)
                } else if self
                    .tool_output_after_model
                    .is_some_and(|tool| date.is_none_or(|stamp| stamp - tool <= 0.1))
                {
                    self.last_output
                } else {
                    date
                }
            } else if self
                .tool_output_after_model
                .is_some_and(|tool| date.is_none_or(|stamp| stamp - tool <= 0.1))
            {
                self.last_output
            } else {
                date
            }?;
            let duration = end - start;
            if duration <= 0.0 || duration > 3600.0 {
                return None;
            }
            let first_token = if self.starts_with_tool_call {
                None
            } else {
                self.first_output
                    .map(|first| first - start)
                    .filter(|first| *first > 0.0 && *first <= duration)
            };
            Some((duration, first_token))
        });
        self.reset(date);
        self.last_token_count = date;
        timing
    }
}
