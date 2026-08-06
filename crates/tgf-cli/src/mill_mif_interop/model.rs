// SPDX-License-Identifier: AGPL-3.0-or-later

use serde_json::{Map, Value, json};

use super::identity;

pub(super) type Result<T> = std::result::Result<T, Diagnostic>;

#[derive(Debug, Clone)]
pub(super) struct Diagnostic {
    category: &'static str,
    code: &'static str,
    message: String,
    event_seq: Option<u64>,
    resource_limit: Option<ResourceLimit>,
}

#[derive(Debug, Clone)]
struct ResourceLimit {
    name: &'static str,
    limit: usize,
    actual: usize,
}

impl Diagnostic {
    pub(super) fn new(
        category: &'static str,
        code: &'static str,
        message: impl Into<String>,
    ) -> Self {
        Self {
            category,
            code,
            message: message.into(),
            event_seq: None,
            resource_limit: None,
        }
    }

    fn at_event(mut self, event_seq: u64) -> Self {
        self.event_seq = Some(event_seq);
        self
    }

    pub(super) fn with_resource_limit(
        mut self,
        name: &'static str,
        limit: usize,
        actual: usize,
    ) -> Self {
        self.resource_limit = Some(ResourceLimit {
            name,
            limit,
            actual,
        });
        self
    }

    pub(super) fn into_value(self) -> Value {
        let mut value = json!({
            "category": self.category,
            "code": self.code,
            "message": self.message,
        });
        if let Some(seq) = self.event_seq {
            value
                .as_object_mut()
                .expect("diagnostic is an object")
                .insert("eventSeq".into(), json!(seq));
        }
        if let Some(resource) = self.resource_limit {
            value
                .as_object_mut()
                .expect("diagnostic is an object")
                .insert(
                    "resourceLimit".into(),
                    json!({
                        "name": resource.name,
                        "limit": resource.limit,
                        "actual": resource.actual,
                    }),
                );
        }
        value
    }
}

pub(super) fn enforce_resource_limit(
    name: &'static str,
    actual: usize,
    limit: usize,
) -> Result<()> {
    if actual > limit {
        return Err(Diagnostic::new(
            "resource",
            "resource-limit",
            format!("{name} resource limit exceeded"),
        )
        .with_resource_limit(name, limit, actual));
    }
    Ok(())
}

pub(super) const COORDS: [&str; 24] = [
    "a7", "d7", "g7", "g4", "g1", "d1", "a1", "a4", "b6", "d6", "f6", "f4", "f2", "d2", "b2", "b4",
    "c5", "d5", "e5", "e4", "e3", "d3", "c3", "c4",
];

const LINES: [[usize; 3]; 16] = [
    [0, 1, 2],
    [2, 3, 4],
    [4, 5, 6],
    [6, 7, 0],
    [8, 9, 10],
    [10, 11, 12],
    [12, 13, 14],
    [14, 15, 8],
    [16, 17, 18],
    [18, 19, 20],
    [20, 21, 22],
    [22, 23, 16],
    [1, 9, 17],
    [3, 11, 19],
    [5, 13, 21],
    [7, 15, 23],
];

const ADJACENCY: [&[usize]; 24] = [
    &[1, 7],
    &[0, 2, 9],
    &[1, 3],
    &[2, 4, 11],
    &[3, 5],
    &[4, 6, 13],
    &[5, 7],
    &[0, 6, 15],
    &[9, 15],
    &[1, 8, 10, 17],
    &[9, 11],
    &[3, 10, 12, 19],
    &[11, 13],
    &[5, 12, 14, 21],
    &[13, 15],
    &[7, 8, 14, 23],
    &[17, 23],
    &[9, 16, 18],
    &[17, 19],
    &[11, 18, 20],
    &[19, 21],
    &[13, 20, 22],
    &[21, 23],
    &[15, 16, 22],
];

#[derive(Clone, Debug, PartialEq, Eq)]
pub(super) struct State {
    pub(super) board: [char; 24],
    pub(super) side: char,
    pub(super) phase: char,
    pub(super) action: char,
    pub(super) hands: [u64; 2],
    pub(super) obligations: String,
    pub(super) no_progress: u64,
    pub(super) primary_ply: u64,
    pub(super) outcome: String,
    pub(super) extensions: Vec<String>,
}

impl State {
    pub(super) fn parse(text: &str) -> Result<Self> {
        let fields: Vec<&str> = text.split_ascii_whitespace().collect();
        if fields.len() < 11 || fields[0] != "MFEN/1.0" || fields[1] != "mill24-state-v1" {
            return Err(Diagnostic::new(
                "syntax",
                "mfen-invalid",
                "MFEN must use MFEN/1.0 mill24-state-v1 and all required fields",
            ));
        }
        let compact_board = fields[2].replace('/', "");
        if compact_board.len() != 24
            || compact_board
                .chars()
                .any(|piece| !matches!(piece, 'W' | 'B' | 'w' | 'b' | '.'))
        {
            return Err(Diagnostic::new(
                "syntax",
                "board-invalid",
                "MFEN board must contain three eight-point rings",
            ));
        }
        let board: [char; 24] = compact_board
            .chars()
            .collect::<Vec<_>>()
            .try_into()
            .expect("validated board has 24 characters");
        let side = one_char(fields[3], "side")?;
        let phase = one_char(fields[4], "phase")?;
        let action = one_char(fields[5], "action")?;
        let hands: Vec<_> = fields[6].split(',').collect();
        if hands.len() != 2 {
            return Err(Diagnostic::new(
                "syntax",
                "hands-invalid",
                "hands must contain white,black counts",
            ));
        }
        let hands = [
            parse_uint(hands[0], "hands")?,
            parse_uint(hands[1], "hands")?,
        ];
        let state = Self {
            board,
            side,
            phase,
            action,
            hands,
            obligations: fields[7].to_string(),
            no_progress: parse_uint(fields[8], "no-progress")?,
            primary_ply: parse_uint(fields[9], "primary-ply")?,
            outcome: fields[10].to_string(),
            extensions: fields[11..]
                .iter()
                .map(|value| (*value).to_string())
                .collect(),
        };
        state.validate_shape()?;
        Ok(state)
    }

    fn validate_shape(&self) -> Result<()> {
        if self.outcome == "-" {
            if !matches!(self.side, 'w' | 'b')
                || !matches!(self.phase, 'p' | 'm')
                || !matches!(self.action, 'p' | 'm' | 'r')
            {
                return Err(Diagnostic::new(
                    "inconsistent",
                    "state-fields-inconsistent",
                    "ongoing side, phase and action are inconsistent",
                ));
            }
        } else if self.side != '-'
            || self.phase != 'o'
            || self.action != 'o'
            || self.obligations != "-"
        {
            return Err(Diagnostic::new(
                "inconsistent",
                "terminal-state-not-normalized",
                "terminal MFEN fields are not normalized",
            ));
        }
        if self.obligations == "-" && self.outcome == "-" && self.action != self.phase {
            return Err(Diagnostic::new(
                "inconsistent",
                "action-phase-mismatch",
                "stable action must match phase",
            ));
        }
        if self.obligations != "-" && self.action != 'r' {
            return Err(Diagnostic::new(
                "inconsistent",
                "obligation-action-mismatch",
                "an obligation requires remove action",
            ));
        }
        Ok(())
    }

    pub(super) fn board_field(&self) -> String {
        let compact: String = self.board.iter().collect();
        format!(
            "{}/{}/{}",
            &compact[0..8],
            &compact[8..16],
            &compact[16..24]
        )
    }

    pub(super) fn canonical(&self) -> String {
        let mut value = format!(
            "MFEN/1.0 mill24-state-v1 {} {} {} {} {},{} {} {} {} {}",
            self.board_field(),
            self.side,
            self.phase,
            self.action,
            self.hands[0],
            self.hands[1],
            self.obligations,
            self.no_progress,
            self.primary_ply,
            self.outcome
        );
        let mut extensions = self.extensions.clone();
        extensions.sort();
        for extension in extensions {
            value.push(' ');
            value.push_str(&extension);
        }
        value
    }

    fn stable(&self) -> bool {
        self.outcome == "-" && self.obligations == "-" && self.action == self.phase
    }

    fn terminal(&mut self, result: char, reason: &str) {
        self.side = '-';
        self.phase = 'o';
        self.action = 'o';
        self.obligations = "-".into();
        self.outcome = format!("{result}:{reason}");
    }

    fn live_count(&self, player: char) -> u64 {
        let piece = player.to_ascii_uppercase();
        self.board.iter().filter(|value| **value == piece).count() as u64
    }
}

fn one_char(value: &str, field: &str) -> Result<char> {
    let mut chars = value.chars();
    let first = chars
        .next()
        .ok_or_else(|| Diagnostic::new("syntax", "mfen-invalid", format!("empty {field} field")))?;
    if chars.next().is_some() {
        return Err(Diagnostic::new(
            "syntax",
            "mfen-invalid",
            format!("invalid {field} field"),
        ));
    }
    Ok(first)
}

fn parse_uint(value: &str, field: &str) -> Result<u64> {
    if value.len() > 1 && value.starts_with('0') {
        return Err(Diagnostic::new(
            "canonical",
            "integer-not-canonical",
            format!("{field} has a leading zero"),
        ));
    }
    value.parse().map_err(|_| {
        Diagnostic::new(
            "syntax",
            "integer-invalid",
            format!("{field} is not an unsigned integer"),
        )
    })
}

#[derive(Clone)]
pub(super) struct Manifest {
    pub(super) value: Value,
    pub(super) semantic_digest: String,
    pub(super) document_digest: String,
    repetition_count: u64,
    repetition_mode: String,
    movement_allowed: bool,
    minimum_live: u64,
    board_full: String,
    no_progress_normal: u64,
    no_progress_endgame: u64,
    no_progress_counted: Vec<String>,
    no_progress_resets: Vec<String>,
    repetition_resets: Vec<String>,
    placing_no_legal: String,
    stalemate_action: String,
}

impl Manifest {
    pub(super) fn new(value: Value) -> Result<Self> {
        let (semantic_digest, document_digest) = identity::manifest_identities(&value)?;
        validate_runtime_manifest(&value)?;
        let repetition = pointer(&value, "/draw/repetition")?;
        let no_progress = pointer(&value, "/draw/noProgress")?;
        Ok(Self {
            repetition_count: member_u64(repetition, "count")?,
            repetition_mode: member_str(repetition, "mode")?.into(),
            movement_allowed: pointer(&value, "/placing/movementAllowed")?
                .as_bool()
                .ok_or_else(|| invalid_manifest("placing.movementAllowed must be boolean"))?,
            minimum_live: pointer(&value, "/pieces/minimumLive")?
                .as_u64()
                .ok_or_else(|| invalid_manifest("pieces.minimumLive must be an integer"))?,
            board_full: pointer(&value, "/boardFull/action")?
                .as_str()
                .ok_or_else(|| invalid_manifest("boardFull.action must be text"))?
                .into(),
            no_progress_normal: member_u64(no_progress, "normalLimit")?,
            no_progress_endgame: member_u64(no_progress, "endgameLimit")?,
            no_progress_counted: string_array(no_progress, "countedPrimaryActions")?,
            no_progress_resets: string_array(no_progress, "resetEvents")?,
            repetition_resets: string_array(repetition, "resetEvents")?,
            placing_no_legal: pointer(&value, "/placing/noLegalPrimaryAction")?
                .as_str()
                .expect("runtime manifest validation checked placing policy")
                .into(),
            stalemate_action: pointer(&value, "/stalemate/action")?
                .as_str()
                .expect("runtime manifest validation checked stalemate action")
                .into(),
            value,
            semantic_digest,
            document_digest,
        })
    }

    fn initial_count(&self, player: char) -> Result<u64> {
        pointer(
            &self.value,
            if player == 'w' {
                "/pieces/white"
            } else {
                "/pieces/black"
            },
        )?
        .as_u64()
        .ok_or_else(|| invalid_manifest("piece count must be an integer"))
    }

    fn repetition_enabled(&self) -> bool {
        self.repetition_count > 0
    }
}

fn validate_runtime_manifest(value: &Value) -> Result<()> {
    let unsupported =
        |message| Diagnostic::new("unsupported", "manifest-profile-unsupported", message);
    if value
        .get("semanticState")
        .and_then(Value::as_array)
        .is_none_or(|features| !features.is_empty())
        || value
            .get("extensions")
            .and_then(Value::as_array)
            .is_some_and(|extensions| !extensions.is_empty())
    {
        return Err(unsupported("semantic state extensions are not implemented"));
    }
    if pointer(value, "/captures/resolution")?.as_str() != Some("target-commits-v1")
        || ["custodian", "intervention", "leap"]
            .iter()
            .any(|mechanism| {
                value
                    .pointer(&format!("/captures/{mechanism}/enabled"))
                    .and_then(Value::as_bool)
                    != Some(false)
            })
    {
        return Err(unsupported("capture mechanisms are not implemented"));
    }
    let mills = pointer(value, "/mills")?;
    let supported_mills = [
        ("placingEffect", "remove-opponent-board"),
        ("movingEffect", "remove-opponent-board"),
        ("removalMultiplicity", "one-per-primary"),
        ("targetProtection", "outside-mill-first"),
        ("lineReuse", "unlimited"),
        ("reverseReformation", "allowed"),
        ("delayedClearBoundary", "on-enter-moving-v1"),
    ];
    if supported_mills
        .iter()
        .any(|(member, expected)| mills.get(*member).and_then(Value::as_str) != Some(*expected))
    {
        return Err(unsupported(
            "selected mill effect profile is not implemented",
        ));
    }
    if !matches!(
        pointer(value, "/boardFull/action")?.as_str(),
        Some(
            "disabled"
                | "white-loses"
                | "draw"
                | "white-then-black-remove"
                | "black-then-white-remove"
        )
    ) {
        return Err(unsupported("selected board-full action is not implemented"));
    }
    if !matches!(
        pointer(value, "/placing/noLegalPrimaryAction")?.as_str(),
        Some("apply-board-full" | "loss" | "draw")
    ) || !matches!(
        pointer(value, "/stalemate/action")?.as_str(),
        Some("loss" | "draw")
    ) {
        return Err(unsupported(
            "selected liveness or stalemate policy is not implemented",
        ));
    }
    if pointer(value, "/placing/noLegalPrimaryAction")?.as_str() == Some("apply-board-full")
        && pointer(value, "/boardFull/action")?.as_str() == Some("disabled")
    {
        return Err(Diagnostic::new(
            "inconsistent",
            "no-legal-primary-action-policy-invalid",
            "apply-board-full requires an enabled board-full action",
        ));
    }
    if pointer(value, "/turn/placingEndActivePlayer")?.as_str() != Some("retain")
        || pointer(value, "/draw/offers/expiry")?.as_str() != Some("explicit-only")
    {
        return Err(unsupported(
            "turn-boundary or offer-expiry profile is not implemented",
        ));
    }
    Ok(())
}

fn pointer<'a>(value: &'a Value, path: &str) -> Result<&'a Value> {
    value.pointer(path).ok_or_else(|| {
        Diagnostic::new(
            "syntax",
            "manifest-member-missing",
            format!("manifest member `{path}` is required"),
        )
    })
}

fn member_u64(value: &Value, member: &str) -> Result<u64> {
    value
        .get(member)
        .and_then(Value::as_u64)
        .ok_or_else(|| invalid_manifest(format!("manifest member `{member}` must be an integer")))
}

fn member_str<'a>(value: &'a Value, member: &str) -> Result<&'a str> {
    value
        .get(member)
        .and_then(Value::as_str)
        .ok_or_else(|| invalid_manifest(format!("manifest member `{member}` must be text")))
}

fn string_array(value: &Value, member: &str) -> Result<Vec<String>> {
    value
        .get(member)
        .and_then(Value::as_array)
        .ok_or_else(|| invalid_manifest(format!("manifest member `{member}` must be an array")))?
        .iter()
        .map(|item| {
            item.as_str().map(str::to_owned).ok_or_else(|| {
                invalid_manifest(format!("manifest member `{member}` must contain text"))
            })
        })
        .collect()
}

fn invalid_manifest(message: impl Into<String>) -> Diagnostic {
    Diagnostic::new("syntax", "manifest-invalid", message)
}

#[derive(Clone)]
struct Engine {
    manifest: Manifest,
    state: State,
    events: Vec<Value>,
    repetition_history: Vec<Value>,
    claims: Vec<Value>,
    pre_origin_claims: Vec<Value>,
    open_offer: Option<OpenOffer>,
    claim_rights: Option<Value>,
    trace: Vec<Value>,
    origin: String,
    origin_generated_obligation: bool,
}

#[derive(Clone)]
struct OpenOffer {
    source: &'static str,
    actor: char,
    event_seq: u64,
}

impl Engine {
    fn new(
        manifest: Manifest,
        origin: &str,
        repetition_seed: Vec<Value>,
        pre_origin_claims: Vec<Value>,
    ) -> Result<Self> {
        enforce_resource_limit(
            "repetition-entries",
            repetition_seed.len(),
            super::MAX_REPETITION_ENTRIES,
        )?;
        let state = State::parse(origin)?;
        for player in ['w', 'b'] {
            let live = state.live_count(player);
            let delayed = state.board.iter().filter(|piece| **piece == player).count() as u64;
            let hand = state.hands[player_index(player)];
            if live + delayed + hand > manifest.initial_count(player)? {
                return Err(Diagnostic::new(
                    "inconsistent",
                    "piece-conservation-invalid",
                    "board plus hand exceeds manifest piece count",
                ));
            }
        }
        let open_offer = open_offer_from_claims(&pre_origin_claims, true)?;
        let origin_had_obligation = state.obligations != "-";
        let mut engine = Self {
            manifest,
            state,
            events: Vec::new(),
            repetition_history: repetition_seed,
            claims: pre_origin_claims.clone(),
            pre_origin_claims,
            open_offer,
            claim_rights: None,
            trace: Vec::new(),
            origin: origin.into(),
            origin_generated_obligation: false,
        };
        engine.stabilize(None, "origin")?;
        engine.origin_generated_obligation =
            !origin_had_obligation && engine.state.obligations != "-";
        engine.trace.push(engine.snapshot("origin", None)?);
        Ok(engine)
    }

    fn execute_events(mut self, events: &[Value]) -> Result<Self> {
        enforce_resource_limit("events", events.len(), super::MAX_EVENTS)?;
        for (index, event) in events.iter().enumerate() {
            let seq = event.get("seq").and_then(Value::as_u64).ok_or_else(|| {
                Diagnostic::new("syntax", "event-seq-missing", "event requires seq")
            })?;
            if seq != (index + 1) as u64 {
                return Err(Diagnostic::new(
                    "inconsistent",
                    "event-sequence-invalid",
                    "event sequences must be consecutive from one",
                )
                .at_event(seq));
            }
            self.apply_event(event, seq)?;
            self.events.push(event.clone());
            self.trace.push(self.snapshot("event", Some(seq))?);
        }
        Ok(self)
    }

    fn apply_event(&mut self, event: &Value, seq: u64) -> Result<()> {
        let event_type = event.get("type").and_then(Value::as_str).ok_or_else(|| {
            Diagnostic::new("syntax", "event-type-missing", "event requires type")
        })?;
        let actor = event.get("actor").and_then(Value::as_str).unwrap_or("");
        match event_type {
            "place" => self.apply_place(event, actor, seq),
            "move" => self.apply_move(event, actor, seq),
            "remove" => self.apply_remove(event, actor, seq),
            "offer-draw" => self.offer_draw(actor, seq),
            "withdraw-draw" | "decline-draw" | "accept-draw" => {
                self.resolve_offer(event, event_type, actor, seq)
            }
            "claim-draw" => self.claim_draw(event, actor, seq),
            "resign" => self.resign(actor, seq),
            "adjudicate" => self.adjudicate(event, actor, seq),
            _ => Err(Diagnostic::new(
                "unsupported",
                "event-type-unsupported",
                format!("unsupported event type `{event_type}`"),
            )
            .at_event(seq)),
        }
    }

    fn require_actor(&self, actor: &str, seq: u64) -> Result<char> {
        let actor = one_char(actor, "actor")?;
        if actor != self.state.side {
            return Err(Diagnostic::new(
                "replay",
                "actor-out-of-turn",
                "event actor is not the current side",
            )
            .at_event(seq));
        }
        Ok(actor)
    }

    fn apply_place(&mut self, event: &Value, actor: &str, seq: u64) -> Result<()> {
        let actor = self.require_actor(actor, seq)?;
        if self.state.action != 'p' || self.state.obligations != "-" {
            return Err(illegal(
                "place-action-mismatch",
                "place is not currently legal",
                seq,
            ));
        }
        let at = event
            .get("at")
            .and_then(Value::as_str)
            .ok_or_else(|| illegal("place-target-missing", "place event requires at", seq))?;
        let index = coord_index(at)
            .ok_or_else(|| illegal("coordinate-invalid", "place coordinate is invalid", seq))?;
        if self.state.board[index] != '.' || self.state.hands[player_index(actor)] == 0 {
            return Err(illegal(
                "place-illegal",
                "place target or hand is invalid",
                seq,
            ));
        }
        self.expire_claim_right();
        self.state.board[index] = actor.to_ascii_uppercase();
        self.state.hands[player_index(actor)] -= 1;
        self.state.primary_ply += 1;
        self.after_primary(actor, index, "place", seq)
    }

    fn apply_move(&mut self, event: &Value, actor: &str, seq: u64) -> Result<()> {
        let actor = self.require_actor(actor, seq)?;
        if !((self.state.action == 'm')
            || (self.state.action == 'p' && self.manifest.movement_allowed))
            || self.state.obligations != "-"
        {
            return Err(illegal(
                "move-action-mismatch",
                "move is not currently legal",
                seq,
            ));
        }
        let from = event
            .get("from")
            .and_then(Value::as_str)
            .ok_or_else(|| illegal("move-source-missing", "move event requires from", seq))?;
        let to = event
            .get("to")
            .and_then(Value::as_str)
            .ok_or_else(|| illegal("move-target-missing", "move event requires to", seq))?;
        let from = coord_index(from)
            .ok_or_else(|| illegal("coordinate-invalid", "move source is invalid", seq))?;
        let to = coord_index(to)
            .ok_or_else(|| illegal("coordinate-invalid", "move target is invalid", seq))?;
        let flying = self
            .manifest
            .value
            .pointer("/flying/enabled")
            .and_then(Value::as_bool)
            == Some(true)
            && self.state.live_count(actor)
                <= self
                    .manifest
                    .value
                    .pointer("/flying/maximumLive")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
        if self.state.board[from] != actor.to_ascii_uppercase()
            || self.state.board[to] != '.'
            || (!flying && !ADJACENCY[from].contains(&to))
        {
            return Err(illegal("move-illegal", "move is not legal", seq));
        }
        self.expire_claim_right();
        self.state.board[from] = '.';
        self.state.board[to] = actor.to_ascii_uppercase();
        self.state.primary_ply += 1;
        self.after_primary(actor, to, "move", seq)
    }

    fn after_primary(
        &mut self,
        actor: char,
        destination: usize,
        kind: &str,
        seq: u64,
    ) -> Result<()> {
        let formed_mill = closes_mill(&self.state.board, actor, destination);
        if (kind == "place"
            && self
                .manifest
                .repetition_resets
                .iter()
                .any(|event| event == "place"))
            || (formed_mill
                && self
                    .manifest
                    .repetition_resets
                    .iter()
                    .any(|event| event == "mill-formation"))
        {
            self.repetition_history.clear();
        }
        let progress_disabled =
            self.manifest.no_progress_normal == 0 && self.manifest.no_progress_endgame == 0;
        let progress_reset = (kind == "place"
            && self
                .manifest
                .no_progress_resets
                .iter()
                .any(|event| event == "place"))
            || (formed_mill
                && self
                    .manifest
                    .no_progress_resets
                    .iter()
                    .any(|event| event == "mill-formation"));
        if progress_disabled || progress_reset {
            self.state.no_progress = 0;
        } else if self
            .manifest
            .no_progress_counted
            .iter()
            .any(|event| event == kind)
        {
            self.state.no_progress += 1;
        }
        if formed_mill {
            let target_owner = opponent(actor);
            let targets = removal_targets(&self.state.board, target_owner);
            if targets != 0 {
                self.state.obligations = format!(
                    "{actor}:mill:b:{target_owner}:1:{targets:06x}:{}",
                    opponent(actor)
                );
                self.state.action = 'r';
                self.state.side = actor;
                return Ok(());
            }
        }
        self.state.side = opponent(actor);
        self.sync_phase();
        self.stabilize(Some(seq), kind)
    }

    fn apply_remove(&mut self, event: &Value, actor: &str, seq: u64) -> Result<()> {
        let actor = self.require_actor(actor, seq)?;
        if self.state.action != 'r' || self.state.obligations == "-" {
            return Err(illegal(
                "remove-without-obligation",
                "remove requires an active obligation",
                seq,
            ));
        }
        let target = event
            .get("target")
            .ok_or_else(|| illegal("remove-target-missing", "remove event requires target", seq))?;
        if target.get("zone").and_then(Value::as_str) != Some("board") {
            return Err(Diagnostic::new(
                "unsupported",
                "hand-removal-unsupported",
                "this adapter currently supports board removal obligations",
            )
            .at_event(seq));
        }
        let at = target
            .get("at")
            .and_then(Value::as_str)
            .ok_or_else(|| illegal("remove-target-missing", "board target requires at", seq))?;
        let index = coord_index(at)
            .ok_or_else(|| illegal("coordinate-invalid", "remove coordinate is invalid", seq))?;
        let mut branches = parse_obligation_branches(&self.state.obligations)?;
        let selected = branches.iter().position(|branch| {
            branch
                .first()
                .is_some_and(|head| head.actor == actor && head.targets & (1 << index) != 0)
        });
        let Some(selected) = selected else {
            return Err(illegal(
                "obligation-target-mismatch",
                "remove target does not satisfy an obligation branch",
                seq,
            ));
        };
        let mut branch = branches.swap_remove(selected);
        let mut head = branch.remove(0);
        let after = head.after;
        if self.state.board[index] != head.owner.to_ascii_uppercase() {
            return Err(illegal(
                "obligation-target-mismatch",
                "remove target owner does not match obligation",
                seq,
            ));
        }
        self.expire_claim_right();
        self.state.board[index] = '.';
        if self
            .manifest
            .no_progress_resets
            .iter()
            .any(|event| event == "board-remove")
        {
            self.state.no_progress = 0;
        }
        if self
            .manifest
            .repetition_resets
            .iter()
            .any(|event| event == "board-remove")
        {
            self.repetition_history.clear();
        }
        head.remaining -= 1;
        if head.remaining > 0 {
            head.targets = removal_targets(&self.state.board, head.owner);
            branch.insert(0, head);
        }
        if let Some(next) = branch.first_mut() {
            if next.targets_deferred {
                next.targets = removal_targets(&self.state.board, next.owner);
                next.targets_deferred = false;
            }
            self.state.side = next.actor;
            self.state.action = 'r';
            self.state.obligations = serialize_branch(&branch);
            return self.check_material();
        }
        self.state.side = after;
        self.state.obligations = "-".into();
        self.sync_phase();
        self.check_material()?;
        self.stabilize(Some(seq), "remove")
    }

    fn offer_draw(&mut self, actor: &str, seq: u64) -> Result<()> {
        let actor = self.require_actor(actor, seq)?;
        if self.open_offer.is_some() {
            return Err(illegal(
                "draw-offer-open",
                "a draw offer is already open",
                seq,
            ));
        }
        self.claims.push(json!({
            "actor": actor.to_string(),
            "eventSeq": seq,
            "kind": "draw-offer",
            "source": "event",
            "status": "open"
        }));
        self.open_offer = Some(OpenOffer {
            source: "event",
            actor,
            event_seq: seq,
        });
        Ok(())
    }

    fn resolve_offer(&mut self, event: &Value, kind: &str, actor: &str, seq: u64) -> Result<()> {
        let actor = one_char(actor, "actor")?;
        let Some(offer) = self.open_offer.clone() else {
            return Err(illegal("draw-offer-missing", "no draw offer is open", seq));
        };
        let reference = event
            .get("offerEventSeq")
            .and_then(Value::as_u64)
            .ok_or_else(|| illegal("offer-reference-missing", "offerEventSeq is required", seq))?;
        if reference != offer.event_seq
            || (kind == "withdraw-draw" && actor != offer.actor)
            || (kind != "withdraw-draw" && actor == offer.actor)
        {
            return Err(illegal(
                "draw-offer-reference-invalid",
                "draw offer reference is invalid",
                seq,
            ));
        }
        let status = match kind {
            "withdraw-draw" => "withdrawn",
            "decline-draw" => "declined",
            "accept-draw" => "accepted",
            _ => unreachable!(),
        };
        let claim = self
            .claims
            .iter_mut()
            .find(|claim| {
                claim.get("kind").and_then(Value::as_str) == Some("draw-offer")
                    && claim.get("status").and_then(Value::as_str) == Some("open")
            })
            .expect("open offer is backed by an audit entry");
        claim["status"] = json!(status);
        claim["resolvedEventSeq"] = json!(seq);
        self.open_offer = None;
        if kind == "accept-draw" {
            self.state.terminal('d', "agreement");
        }
        Ok(())
    }

    fn claim_draw(&mut self, event: &Value, actor: &str, seq: u64) -> Result<()> {
        let actor = self.require_actor(actor, seq)?;
        if self.state.obligations != "-" {
            return Err(illegal(
                "claim-during-obligation",
                "cannot claim during removal",
                seq,
            ));
        }
        let reason = event.get("reason").and_then(Value::as_str).unwrap_or("");
        let available = self
            .claim_rights
            .as_ref()
            .and_then(|rights| rights.get("reasons"))
            .and_then(Value::as_array)
            .is_some_and(|reasons| reasons.iter().any(|value| value.as_str() == Some(reason)));
        if !available {
            return Err(illegal(
                "claim-right-unavailable",
                "claim right is unavailable",
                seq,
            ));
        }
        self.state.terminal('d', reason);
        self.claim_rights = None;
        self.open_offer = None;
        self.claims.push(json!({
            "actor": actor.to_string(), "eventSeq": seq, "kind": "draw-claim",
            "reason": reason, "source": "event", "status": "accepted"
        }));
        Ok(())
    }

    fn resign(&mut self, actor: &str, seq: u64) -> Result<()> {
        let actor = one_char(actor, "actor")?;
        if !matches!(actor, 'w' | 'b') || self.state.outcome != "-" {
            return Err(illegal(
                "resignation-invalid",
                "resignation is invalid",
                seq,
            ));
        }
        self.state.terminal(opponent(actor), "resignation");
        self.open_offer = None;
        self.claim_rights = None;
        Ok(())
    }

    fn adjudicate(&mut self, event: &Value, actor: &str, seq: u64) -> Result<()> {
        if actor != "system" {
            return Err(illegal(
                "adjudication-actor-invalid",
                "adjudication actor must be system",
                seq,
            ));
        }
        let result = event.get("result").and_then(Value::as_str).unwrap_or("");
        let result = one_char(result, "result")?;
        if !matches!(result, 'w' | 'b' | 'd') {
            return Err(illegal(
                "adjudication-result-invalid",
                "adjudication result is invalid",
                seq,
            ));
        }
        self.state.terminal(result, "adjudication");
        self.open_offer = None;
        self.claim_rights = None;
        Ok(())
    }

    fn sync_phase(&mut self) {
        if self.state.outcome != "-" || self.state.obligations != "-" {
            return;
        }
        self.state.phase =
            if self.state.hands == [0, 0] || self.state.hands[player_index(self.state.side)] == 0 {
                'm'
            } else {
                'p'
            };
        self.state.action = self.state.phase;
    }

    fn legal_move_exists(&self, player: char) -> bool {
        if !self.state.board.contains(&'.') {
            return false;
        }
        let flying = self
            .manifest
            .value
            .pointer("/flying/enabled")
            .and_then(Value::as_bool)
            == Some(true)
            && self.state.live_count(player)
                <= self
                    .manifest
                    .value
                    .pointer("/flying/maximumLive")
                    .and_then(Value::as_u64)
                    .unwrap_or(0);
        let piece = player.to_ascii_uppercase();
        self.state.board.iter().enumerate().any(|(source, value)| {
            *value == piece
                && (flying
                    || ADJACENCY[source]
                        .iter()
                        .any(|target| self.state.board[*target] == '.'))
        })
    }

    fn legal_primary_exists(&self) -> bool {
        let player = self.state.side;
        if self.state.phase == 'p' {
            (self.state.hands[player_index(player)] > 0 && self.state.board.contains(&'.'))
                || (self.manifest.movement_allowed && self.legal_move_exists(player))
        } else {
            self.legal_move_exists(player)
        }
    }

    fn stabilize(&mut self, event_seq: Option<u64>, source_kind: &str) -> Result<()> {
        if self.state.outcome != "-" || self.state.obligations != "-" {
            return Ok(());
        }
        self.sync_phase();
        if !self.state.board.contains(&'.') {
            match self.manifest.board_full.as_str() {
                "disabled" => {}
                "white-loses" => {
                    self.state.terminal('b', "board-full");
                    return Ok(());
                }
                "draw" => {
                    self.state.terminal('d', "board-full");
                    return Ok(());
                }
                "white-then-black-remove" => {
                    let black_targets = removal_targets(&self.state.board, 'b');
                    self.state.side = 'w';
                    self.state.action = 'r';
                    self.state.obligations =
                        format!("w:board-full:b:b:1:{black_targets:06x}:q;b:board-full:b:w:1:~:w");
                    return Ok(());
                }
                "black-then-white-remove" => {
                    let white_targets = removal_targets(&self.state.board, 'w');
                    self.state.side = 'b';
                    self.state.action = 'r';
                    self.state.obligations =
                        format!("b:board-full:b:w:1:{white_targets:06x}:q;w:board-full:b:b:1:~:b");
                    return Ok(());
                }
                other => {
                    return Err(Diagnostic::new(
                        "unsupported",
                        "board-full-action-unsupported",
                        format!("board-full action `{other}` is not implemented"),
                    ));
                }
            }
        }
        self.check_material()?;
        if self.state.outcome != "-" {
            return Ok(());
        }
        self.sync_phase();
        if !self.legal_primary_exists() {
            if self.state.phase == 'p' {
                match self.manifest.placing_no_legal.as_str() {
                    "loss" => self
                        .state
                        .terminal(opponent(self.state.side), "no-legal-primary-action"),
                    "draw" => self.state.terminal('d', "no-legal-primary-action"),
                    "apply-board-full" => {
                        return Err(Diagnostic::new(
                            "unreachable",
                            "board-full-trigger-unreachable",
                            "apply-board-full was selected outside its full-board trigger",
                        ));
                    }
                    _ => unreachable!("runtime manifest validation checked placing policy"),
                }
            } else {
                match self.manifest.stalemate_action.as_str() {
                    "loss" => self
                        .state
                        .terminal(opponent(self.state.side), "no-legal-move"),
                    "draw" => self.state.terminal('d', "no-legal-move"),
                    _ => unreachable!("runtime manifest validation checked stalemate policy"),
                }
            }
            return Ok(());
        }
        if self.should_observe() {
            let entry = self.observation_entry(event_seq, source_kind)?;
            enforce_resource_limit(
                "repetition-entries",
                self.repetition_history.len().saturating_add(1),
                super::MAX_REPETITION_ENTRIES,
            )?;
            self.repetition_history.push(entry);
            self.apply_repetition_result()?;
        }
        self.derive_claim_rights()?;
        Ok(())
    }

    fn check_material(&mut self) -> Result<()> {
        let white_low =
            self.state.live_count('w') + self.state.hands[0] < self.manifest.minimum_live;
        let black_low =
            self.state.live_count('b') + self.state.hands[1] < self.manifest.minimum_live;
        match (white_low, black_low) {
            (true, true) => self.state.terminal('d', "fewer-than-minimum"),
            (true, false) => self.state.terminal('b', "fewer-than-minimum"),
            (false, true) => self.state.terminal('w', "fewer-than-minimum"),
            (false, false) => {}
        }
        Ok(())
    }

    fn should_observe(&self) -> bool {
        self.manifest.repetition_enabled() && self.state.stable()
    }

    fn observation(&self) -> Value {
        json!({
            "profile": "repetition-observation-v1",
            "stateProfile": "mill24-state-v1",
            "semanticDigest": self.manifest.semantic_digest,
            "board": self.state.board_field(),
            "side": self.state.side.to_string(),
            "phase": self.state.phase.to_string(),
            "action": self.state.action.to_string(),
            "hands": self.state.hands,
            "semantic": semantic_state(&self.state),
        })
    }

    fn observation_entry(&self, event_seq: Option<u64>, source_kind: &str) -> Result<Value> {
        let mut entry = json!({
            "source": if event_seq.is_some() { "event" } else { source_kind },
            "key": self.observation(),
        });
        if let Some(seq) = event_seq {
            entry["eventSeq"] = json!(seq);
        }
        Ok(entry)
    }

    fn apply_repetition_result(&mut self) -> Result<()> {
        let current = self.observation();
        let count = self
            .repetition_history
            .iter()
            .filter(|entry| entry.get("key") == Some(&current))
            .count() as u64;
        if count < self.manifest.repetition_count {
            return Ok(());
        }
        if self.manifest.repetition_mode == "automatic" {
            self.state.terminal('d', "repetition");
        }
        Ok(())
    }

    fn derive_claim_rights(&mut self) -> Result<()> {
        if !self.state.stable() {
            self.claim_rights = None;
            return Ok(());
        }
        let mut reasons = Vec::new();
        let no_progress_limit = self
            .manifest
            .no_progress_normal
            .max(self.manifest.no_progress_endgame);
        if no_progress_limit > 0 && self.state.no_progress >= no_progress_limit {
            reasons.push(json!("no-progress"));
        }
        if self.manifest.repetition_mode == "claim" && self.manifest.repetition_count > 0 {
            let current = self.observation();
            let count = self
                .repetition_history
                .iter()
                .filter(|entry| entry.get("key") == Some(&current))
                .count() as u64;
            if count >= self.manifest.repetition_count {
                reasons.push(json!("repetition"));
            }
        }
        self.claim_rights = if reasons.is_empty() {
            None
        } else {
            Some(json!({ "actor": self.state.side.to_string(), "reasons": reasons }))
        };
        Ok(())
    }

    fn expire_claim_right(&mut self) {
        self.claim_rights = None;
    }

    fn snapshot(&self, boundary: &str, event_seq: Option<u64>) -> Result<Value> {
        let decision = self.decision_state()?;
        Ok(json!({
            "boundary": boundary,
            "eventSeq": event_seq,
            "current": self.state.canonical(),
            "repetitionHistory": self.repetition_history,
            "claims": self.claims,
            "claimRights": self.claim_rights,
            "decisionState": decision,
            "decisionDigest": identity::digest_json(&decision),
        }))
    }

    fn decision_state(&self) -> Result<Value> {
        let repetition_summary = if self.manifest.repetition_enabled() {
            Some(json!({
                "profile": "reset-count-smt-v1",
                "root": identity::repetition_root(
                    &self.repetition_history,
                    self.manifest.repetition_count,
                )?,
            }))
        } else {
            None
        };
        let no_progress_limit = self
            .manifest
            .no_progress_normal
            .max(self.manifest.no_progress_endgame);
        Ok(json!({
            "profile": "decision-state-v1",
            "stateProfile": "mill24-state-v1",
            "semanticDigest": self.manifest.semantic_digest,
            "board": self.state.board_field(),
            "side": self.state.side.to_string(),
            "phase": self.state.phase.to_string(),
            "action": self.state.action.to_string(),
            "hands": self.state.hands,
            "obligations": self.state.obligations,
            "noProgress": if no_progress_limit == 0 {
                Value::Null
            } else {
                json!(self.state.no_progress.min(no_progress_limit))
            },
            "outcome": self.state.outcome,
            "semantic": semantic_state(&self.state),
            "repetitionSummary": repetition_summary,
            "openOffer": self.decision_offer(),
            "claimRights": self.claim_rights,
        }))
    }

    fn decision_offer(&self) -> Option<Value> {
        if self.state.outcome != "-" {
            return None;
        }
        self.open_offer.as_ref().map(|offer| {
            let other = opponent(offer.actor);
            let available = if offer.actor == 'w' {
                vec![
                    json!({ "actor": "w", "action": "withdraw" }),
                    json!({ "actor": "b", "action": "accept" }),
                    json!({ "actor": "b", "action": "decline" }),
                ]
            } else {
                vec![
                    json!({ "actor": other.to_string(), "action": "accept" }),
                    json!({ "actor": other.to_string(), "action": "decline" }),
                    json!({ "actor": "b", "action": "withdraw" }),
                ]
            };
            json!({ "offerer": offer.actor.to_string(), "available": available })
        })
    }

    fn resumption_state(&self) -> Value {
        let pre_origin_repetition: Vec<_> = self
            .repetition_history
            .iter()
            .take_while(|entry| entry.get("source").and_then(Value::as_str) == Some("pre-origin"))
            .cloned()
            .collect();
        let prefix = json!({
            "origin": self.origin,
            "preOriginRepetition": pre_origin_repetition,
            "preOriginClaims": self.pre_origin_claims,
            "events": self.events,
        });
        let open_offer = self.open_offer.as_ref().map(|offer| {
            json!({
                "source": offer.source,
                "actor": offer.actor.to_string(),
                "offerEventSeq": offer.event_seq,
            })
        });
        json!({
            "profile": "resumption-state-v1",
            "positionFormat": "MFEN/1.0",
            "stateProfile": "mill24-state-v1",
            "semanticDigest": self.manifest.semantic_digest,
            "current": self.state.canonical(),
            "replayPrefixDigest": identity::digest_json(&prefix),
            "lastEventSeq": self.events.last().and_then(|event| event.get("seq")).and_then(Value::as_u64).unwrap_or(0),
            "repetitionHistory": self.repetition_history,
            "claims": self.claims,
            "openOffer": open_offer,
            "claimRights": self.claim_rights,
        })
    }
}

fn semantic_state(state: &State) -> Value {
    let mut semantic = Map::new();
    for extension in &state.extensions {
        if let Some((key, value)) = extension.split_once('=') {
            semantic.insert(key.into(), json!(value));
        }
    }
    Value::Object(semantic)
}

fn illegal(code: &'static str, message: impl Into<String>, seq: u64) -> Diagnostic {
    Diagnostic::new("replay", code, message).at_event(seq)
}

fn player_index(player: char) -> usize {
    usize::from(player == 'b')
}

pub(super) fn opponent(player: char) -> char {
    if player == 'w' { 'b' } else { 'w' }
}

pub(super) fn coord_index(coord: &str) -> Option<usize> {
    COORDS.iter().position(|candidate| *candidate == coord)
}

fn closes_mill(board: &[char; 24], player: char, destination: usize) -> bool {
    let piece = player.to_ascii_uppercase();
    LINES
        .iter()
        .any(|line| line.contains(&destination) && line.iter().all(|index| board[*index] == piece))
}

fn in_mill(board: &[char; 24], owner: char, index: usize) -> bool {
    closes_mill(board, owner, index)
}

fn removal_targets(board: &[char; 24], owner: char) -> u32 {
    let piece = owner.to_ascii_uppercase();
    let outside: Vec<_> = board
        .iter()
        .enumerate()
        .filter(|(index, value)| **value == piece && !in_mill(board, owner, *index))
        .map(|(index, _)| index)
        .collect();
    let candidates: Vec<_> = if outside.is_empty() {
        board
            .iter()
            .enumerate()
            .filter(|(_, value)| **value == piece)
            .map(|(index, _)| index)
            .collect()
    } else {
        outside
    };
    candidates
        .into_iter()
        .fold(0_u32, |mask, index| mask | (1 << index))
}

#[derive(Clone)]
struct Obligation {
    actor: char,
    cause: String,
    zone: char,
    owner: char,
    remaining: u64,
    targets: u32,
    targets_deferred: bool,
    after: char,
}

fn parse_obligation_branches(value: &str) -> Result<Vec<Vec<Obligation>>> {
    value
        .split('|')
        .map(|branch| branch.split(';').map(parse_obligation).collect())
        .collect()
}

fn parse_obligation(value: &str) -> Result<Obligation> {
    let fields: Vec<_> = value.split(':').collect();
    if fields.len() != 7 {
        return Err(Diagnostic::new(
            "syntax",
            "obligation-invalid",
            "obligation requires seven fields",
        ));
    }
    let targets_deferred = fields[5] == "~";
    let targets = if targets_deferred || fields[5] == "-" {
        0
    } else {
        u32::from_str_radix(fields[5], 16).map_err(|_| {
            Diagnostic::new("syntax", "obligation-invalid", "invalid target bit set")
        })?
    };
    Ok(Obligation {
        actor: one_char(fields[0], "obligation actor")?,
        cause: fields[1].into(),
        zone: one_char(fields[2], "obligation zone")?,
        owner: one_char(fields[3], "obligation owner")?,
        remaining: parse_uint(fields[4], "obligation remaining")?,
        targets,
        targets_deferred,
        after: one_char(fields[6], "obligation after")?,
    })
}

fn serialize_branch(branch: &[Obligation]) -> String {
    branch
        .iter()
        .map(|obligation| {
            format!(
                "{}:{}:{}:{}:{}:{}:{}",
                obligation.actor,
                obligation.cause,
                obligation.zone,
                obligation.owner,
                obligation.remaining,
                if obligation.targets_deferred {
                    "~".into()
                } else if obligation.zone == 'h' {
                    "-".into()
                } else {
                    format!("{:06x}", obligation.targets)
                },
                obligation.after
            )
        })
        .collect::<Vec<_>>()
        .join(";")
}

fn open_offer_from_claims(claims: &[Value], pre_origin: bool) -> Result<Option<OpenOffer>> {
    let open: Vec<_> = claims
        .iter()
        .filter(|claim| {
            claim.get("kind").and_then(Value::as_str) == Some("draw-offer")
                && claim.get("status").and_then(Value::as_str) == Some("open")
        })
        .collect();
    if open.len() > 1 {
        return Err(Diagnostic::new(
            "inconsistent",
            "multiple-open-offers",
            "claim seed contains multiple open offers",
        ));
    }
    open.first()
        .map(|claim| {
            Ok(OpenOffer {
                source: if pre_origin { "pre-origin" } else { "event" },
                actor: one_char(
                    claim.get("actor").and_then(Value::as_str).unwrap_or(""),
                    "offer actor",
                )?,
                event_seq: if pre_origin {
                    0
                } else {
                    claim.get("eventSeq").and_then(Value::as_u64).unwrap_or(0)
                },
            })
        })
        .transpose()
}

pub(super) fn canonicalize(payload: &Value) -> Result<Value> {
    let format = payload.get("format").and_then(Value::as_str).unwrap_or("");
    let value = payload
        .get("value")
        .and_then(Value::as_str)
        .ok_or_else(|| Diagnostic::new("syntax", "value-missing", "canonicalize requires value"))?;
    match format {
        "MFEN/1.0" => {
            let manifest = payload.get("manifest").cloned().ok_or_else(|| {
                Diagnostic::new(
                    "integrity",
                    "manifest-missing",
                    "MFEN canonicalization requires caller ruleset context",
                )
            })?;
            let _manifest = Manifest::new(manifest)?;
            Ok(json!({ "value": State::parse(value)?.canonical() }))
        }
        "MPK/1.0" => canonicalize_mpk(value, payload.get("manifest")),
        _ => Err(Diagnostic::new(
            "unsupported",
            "format-unsupported",
            format!("canonicalization format `{format}` is unsupported"),
        )),
    }
}

fn canonicalize_mpk(value: &str, manifest_value: Option<&Value>) -> Result<Value> {
    let manifest = Manifest::new(manifest_value.cloned().ok_or_else(|| {
        Diagnostic::new(
            "integrity",
            "manifest-missing",
            "MPK binding requires caller ruleset context",
        )
    })?)?;
    let fields: Vec<_> = value.split_ascii_whitespace().collect();
    if fields.len() != 9 || fields[0] != "MPK/1.0" || fields[1] != "mill24-state-v1" {
        return Err(Diagnostic::new(
            "syntax",
            "mpk-invalid",
            "MPK/1.0 value is incomplete",
        ));
    }
    let expected_reference = format!(
        "{}@{}",
        manifest
            .value
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or(""),
        manifest
            .value
            .get("version")
            .and_then(Value::as_u64)
            .unwrap_or(0)
    );
    if fields[2] != expected_reference {
        return Err(Diagnostic::new(
            "integrity",
            "ruleset-identity-mismatch",
            "MPK ruleset reference does not match manifest",
        ));
    }
    if fields[3] != manifest.semantic_digest {
        return Err(Diagnostic::new(
            "integrity",
            "semantic-digest-mismatch",
            "MPK semantic digest does not match manifest",
        ));
    }
    if fields[4] != "structural-d4-v1" {
        return Err(Diagnostic::new(
            "unsupported",
            "key-profile-unsupported",
            "only structural-d4-v1 is implemented",
        ));
    }
    if fields[5].len() != 24
        || fields[5].contains('/')
        || fields[5]
            .chars()
            .any(|piece| !matches!(piece, 'W' | 'B' | 'w' | 'b' | '.'))
    {
        return Err(Diagnostic::new(
            "syntax",
            "mpk-board-invalid",
            "MPK board must contain 24 points without separators",
        ));
    }
    if !matches!(fields[6], "w" | "b") || !matches!(fields[7], "p" | "m") {
        return Err(Diagnostic::new(
            "syntax",
            "mpk-state-invalid",
            "MPK side and phase must be active",
        ));
    }
    let hands: Vec<_> = fields[8].split(',').collect();
    if hands.len() != 2 {
        return Err(Diagnostic::new(
            "syntax",
            "hands-invalid",
            "MPK hands require white,black",
        ));
    }
    let hands = format!(
        "{},{}",
        parse_uint(hands[0], "hands")?,
        parse_uint(hands[1], "hands")?
    );
    let mut candidates = Vec::with_capacity(8);
    for transform in [
        "i",
        "r90ccw",
        "r180",
        "r90cw",
        "mirror-v",
        "mirror-h",
        "mirror-main",
        "mirror-anti",
    ] {
        candidates.push(format!(
            "MPK/1.0 mill24-state-v1 {} {} structural-d4-v1 {} {} {} {}",
            expected_reference,
            manifest.semantic_digest,
            super::transform::transform_mpk_board(fields[5], transform)?,
            fields[6],
            fields[7],
            hands
        ));
    }
    candidates.sort();
    Ok(json!({ "value": candidates.remove(0) }))
}

pub(super) fn execute_request(payload: &Value) -> Result<Value> {
    let manifest = Manifest::new(payload.get("manifest").cloned().ok_or_else(|| {
        Diagnostic::new("integrity", "manifest-missing", "execute requires manifest")
    })?)?;
    let origin = payload
        .get("origin")
        .and_then(Value::as_str)
        .ok_or_else(|| Diagnostic::new("syntax", "origin-missing", "execute requires origin"))?;
    let events = array(payload, "events")?;
    let repetition_seed = array(payload, "repetitionSeed")?.to_vec();
    let pre_origin_claims = array(payload, "preOriginClaims")?.to_vec();
    let engine = Engine::new(manifest, origin, repetition_seed, pre_origin_claims)?
        .execute_events(events)?;
    Ok(json!({
        "trace": engine.trace,
        "final": engine.trace.last().expect("trace always contains origin"),
    }))
}

pub(super) fn replay_request(payload: &Value) -> Result<Value> {
    let mstate = payload
        .get("mstate")
        .ok_or_else(|| Diagnostic::new("syntax", "mstate-missing", "replay requires mstate"))?;
    let manifest_value = resolve_manifest(payload.get("manifest"), mstate)?;
    let manifest = Manifest::new(manifest_value)?;
    verify_ruleset_envelope(mstate, &manifest)?;
    let origin = member_text(mstate, "origin")?;
    let supplied_history = array(mstate, "repetitionHistory")?;
    enforce_resource_limit(
        "repetition-entries",
        supplied_history.len(),
        super::MAX_REPETITION_ENTRIES,
    )?;
    let repetition_seed: Vec<_> = supplied_history
        .iter()
        .take_while(|entry| entry.get("source").and_then(Value::as_str) == Some("pre-origin"))
        .cloned()
        .collect();
    let pre_origin_claims = array(mstate, "preOriginClaims")?.to_vec();
    let engine = Engine::new(manifest, origin, repetition_seed, pre_origin_claims)?
        .execute_events(array(mstate, "events")?)?;
    if engine.state.canonical() != member_text(mstate, "current")? {
        return Err(Diagnostic::new(
            "replay",
            "checkpoint-mismatch",
            "replayed current state differs from MSTATE checkpoint",
        ));
    }
    if engine.repetition_history != supplied_history {
        return Err(Diagnostic::new(
            "replay",
            "repetition-history-mismatch",
            "replayed repetition history differs from MSTATE",
        ));
    }
    if engine.claims != array(mstate, "claims")? {
        return Err(Diagnostic::new(
            "replay",
            "claim-audit-mismatch",
            "replayed claim audit differs from MSTATE",
        ));
    }
    replay_result(&engine)
}

fn replay_result(engine: &Engine) -> Result<Value> {
    let decision = engine.decision_state()?;
    let resumption = engine.resumption_state();
    Ok(json!({
        "current": engine.state.canonical(),
        "trace": engine.trace,
        "repetitionHistory": engine.repetition_history,
        "claims": engine.claims,
        "claimRights": engine.claim_rights,
        "decisionState": decision,
        "decisionDigest": identity::digest_json(&decision),
        "resumptionState": resumption,
        "resumptionDigest": identity::digest_json(&resumption),
    }))
}

pub(super) fn project_logical_turns(payload: &Value) -> Result<Value> {
    let mstate = payload.get("mstate").ok_or_else(|| {
        Diagnostic::new(
            "syntax",
            "mstate-missing",
            "logical-turn projection requires mstate",
        )
    })?;
    let manifest = Manifest::new(resolve_manifest(payload.get("manifest"), mstate)?)?;
    verify_ruleset_envelope(mstate, &manifest)?;
    let supplied_history = array(mstate, "repetitionHistory")?;
    enforce_resource_limit(
        "repetition-entries",
        supplied_history.len(),
        super::MAX_REPETITION_ENTRIES,
    )?;
    let seed: Vec<_> = supplied_history
        .iter()
        .take_while(|entry| entry.get("source").and_then(Value::as_str) == Some("pre-origin"))
        .cloned()
        .collect();
    let engine = Engine::new(
        manifest,
        member_text(mstate, "origin")?,
        seed,
        array(mstate, "preOriginClaims")?.to_vec(),
    )?
    .execute_events(array(mstate, "events")?)?;
    if engine.state.canonical() != member_text(mstate, "current")?
        || engine.repetition_history != supplied_history
        || engine.claims != array(mstate, "claims")?
    {
        return Err(Diagnostic::new(
            "replay",
            "mstate-evidence-mismatch",
            "logical-turn projection requires a replay-valid MSTATE",
        ));
    }
    let resumption = engine.resumption_state();
    let events = array(mstate, "events")?;
    let mut fragments = Vec::new();
    let mut index = 0;
    if !snapshot_closed(&engine.trace[0]) {
        let mut removes = Vec::new();
        let mut complete = false;
        while index < events.len() {
            let event = &events[index];
            if event.get("type").and_then(Value::as_str) != Some("remove") {
                break;
            }
            let seq = event.get("seq").and_then(Value::as_u64).unwrap_or(0);
            removes.push(seq);
            complete = snapshot_closed(&engine.trace[seq as usize]);
            index += 1;
            if complete {
                break;
            }
        }
        fragments.push(json!({
                "kind": if engine.origin_generated_obligation {
                    "origin-stabilization"
                } else {
                    "origin-obligation"
                },
                "removeEventSeqs": removes,
                "status": if complete { "complete" } else { "truncated" },
        }));
    }
    while index < events.len() {
        let event = &events[index];
        if !matches!(
            event.get("type").and_then(Value::as_str),
            Some("place" | "move")
        ) {
            index += 1;
            continue;
        }
        let primary = event.get("seq").and_then(Value::as_u64).unwrap_or(0);
        let mut complete = snapshot_closed(&engine.trace[primary as usize]);
        let mut removes = Vec::new();
        index += 1;
        while index < events.len() && !complete {
            let consequent = &events[index];
            if consequent.get("type").and_then(Value::as_str) != Some("remove") {
                break;
            }
            let seq = consequent.get("seq").and_then(Value::as_u64).unwrap_or(0);
            removes.push(seq);
            complete = snapshot_closed(&engine.trace[seq as usize]);
            index += 1;
        }
        fragments.push(logical_fragment(
            primary,
            &removes,
            if complete { "complete" } else { "truncated" },
        ));
    }
    Ok(json!({
        "document": {
            "format": "MIFTURN/1.0",
            "profile": "logical-turn-v1",
            "sourceResumptionDigest": identity::digest_json(&resumption),
            "fragments": fragments,
        }
    }))
}

fn snapshot_closed(snapshot: &Value) -> bool {
    snapshot
        .pointer("/decisionState/action")
        .and_then(Value::as_str)
        != Some("r")
}

fn logical_fragment(primary: u64, removes: &[u64], status: &str) -> Value {
    json!({
        "kind": "logical-turn",
        "primaryEventSeq": primary,
        "removeEventSeqs": removes,
        "status": status,
    })
}

pub(super) fn replay_document(mstate: &Value, manifest_value: Value) -> Result<Value> {
    replay_request(&json!({ "mstate": mstate, "manifest": manifest_value }))
}

pub(super) fn resolve_manifest(explicit: Option<&Value>, document: &Value) -> Result<Value> {
    let (ruleset, mode) = ruleset_envelope(document)?;
    match mode {
        "portable" => {
            let embedded = ruleset
                .get("manifest")
                .expect("portable envelope validation requires a manifest");
            if explicit.is_some_and(|manifest| manifest != embedded) {
                return Err(Diagnostic::new(
                    "integrity",
                    "manifest-conflict",
                    "caller and portable manifests differ",
                ));
            }
            Ok(embedded.clone())
        }
        "reference" => explicit.cloned().ok_or_else(|| {
            Diagnostic::new(
                "integrity",
                "manifest-missing",
                "reference ruleset requires caller resolver",
            )
        }),
        _ => unreachable!("ruleset envelope validation checked mode"),
    }
}

pub(super) fn verify_ruleset_envelope(document: &Value, manifest: &Manifest) -> Result<()> {
    let (ruleset, _) = ruleset_envelope(document)?;
    let expected_id = manifest.value.get("id").and_then(Value::as_str);
    let expected_version = manifest.value.get("version").and_then(Value::as_u64);
    if ruleset.get("id").and_then(Value::as_str) != expected_id
        || ruleset.get("version").and_then(Value::as_u64) != expected_version
    {
        return Err(Diagnostic::new(
            "integrity",
            "manifest-conflict",
            "ruleset identity disagrees with resolved manifest",
        ));
    }
    if ruleset.get("semanticDigest").and_then(Value::as_str) != Some(&manifest.semantic_digest) {
        return Err(Diagnostic::new(
            "integrity",
            "semantic-digest-mismatch",
            "ruleset semantic digest disagrees with resolved manifest",
        ));
    }
    if let Some(document_digest) = ruleset.get("documentDigest")
        && document_digest.as_str() != Some(&manifest.document_digest)
    {
        return Err(Diagnostic::new(
            "integrity",
            "document-digest-mismatch",
            "ruleset document digest disagrees with resolved manifest",
        ));
    }
    Ok(())
}

fn ruleset_envelope(document: &Value) -> Result<(&Map<String, Value>, &str)> {
    let ruleset = document
        .get("ruleset")
        .ok_or_else(|| Diagnostic::new("syntax", "ruleset-missing", "document requires ruleset"))?
        .as_object()
        .ok_or_else(|| {
            Diagnostic::new(
                "syntax",
                "closed-object-mismatch",
                "ruleset envelope must be an object",
            )
        })?;
    let required = ["mode", "id", "version", "semanticDigest"];
    let optional = ["documentDigest", "manifest"];
    if let Some(member) = ruleset
        .keys()
        .find(|member| !required.contains(&member.as_str()) && !optional.contains(&member.as_str()))
    {
        return Err(Diagnostic::new(
            "syntax",
            "closed-object-mismatch",
            format!("ruleset envelope contains unknown member `{member}`"),
        ));
    }
    if let Some(member) = required
        .iter()
        .find(|member| !ruleset.contains_key(**member))
    {
        return Err(Diagnostic::new(
            "syntax",
            "closed-object-mismatch",
            format!("ruleset envelope lacks required member `{member}`"),
        ));
    }
    let mode = ruleset.get("mode").and_then(Value::as_str).ok_or_else(|| {
        Diagnostic::new(
            "syntax",
            "invalid-ruleset-mode",
            "ruleset mode must be portable or reference",
        )
    })?;
    match mode {
        "portable" => {
            if !ruleset.contains_key("manifest") || !ruleset.contains_key("documentDigest") {
                return Err(Diagnostic::new(
                    "integrity",
                    "manifest-missing",
                    "portable ruleset requires manifest and documentDigest",
                ));
            }
        }
        "reference" => {
            if ruleset.contains_key("manifest") {
                return Err(Diagnostic::new(
                    "syntax",
                    "closed-object-mismatch",
                    "reference ruleset must not embed a manifest",
                ));
            }
        }
        _ => {
            return Err(Diagnostic::new(
                "syntax",
                "invalid-ruleset-mode",
                "ruleset mode must be portable or reference",
            ));
        }
    }
    Ok((ruleset, mode))
}

fn array<'a>(value: &'a Value, member: &str) -> Result<&'a [Value]> {
    value
        .get(member)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .ok_or_else(|| {
            Diagnostic::new(
                "syntax",
                "array-member-missing",
                format!("member `{member}` must be an array"),
            )
        })
}

fn member_text<'a>(value: &'a Value, member: &str) -> Result<&'a str> {
    value.get(member).and_then(Value::as_str).ok_or_else(|| {
        Diagnostic::new(
            "syntax",
            "text-member-missing",
            format!("member `{member}` must be text"),
        )
    })
}
