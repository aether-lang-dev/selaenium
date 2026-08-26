//! A tiny, dependency-free JSON encoder/decoder — just enough to marshal
//! WebDriver command params and response values across the FFI. Keeps the crate
//! free of serde so it builds fully offline. Values are represented by [`Json`].

use std::collections::BTreeMap;
use std::fmt::Write as _;

/// A JSON value. Objects preserve nothing about key order on decode (a BTreeMap
/// is used); the WebDriver protocol never relies on response key order.
#[derive(Debug, Clone, PartialEq)]
pub enum Json {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Json>),
    Obj(BTreeMap<String, Json>),
}

impl Json {
    pub fn as_str(&self) -> Option<&str> {
        match self {
            Json::Str(s) => Some(s),
            _ => None,
        }
    }
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Json::Num(n) => Some(*n),
            _ => None,
        }
    }
    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Json::Bool(b) => Some(*b),
            _ => None,
        }
    }
    pub fn as_array(&self) -> Option<&Vec<Json>> {
        match self {
            Json::Arr(a) => Some(a),
            _ => None,
        }
    }
    pub fn get(&self, key: &str) -> Option<&Json> {
        match self {
            Json::Obj(m) => m.get(key),
            _ => None,
        }
    }

    // ---- encode ----
    pub fn encode(&self) -> String {
        let mut s = String::new();
        self.write(&mut s);
        s
    }

    fn write(&self, out: &mut String) {
        match self {
            Json::Null => out.push_str("null"),
            Json::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Json::Num(n) => {
                if n.fract() == 0.0 && n.is_finite() {
                    let _ = write!(out, "{}", *n as i64);
                } else {
                    let _ = write!(out, "{}", n);
                }
            }
            Json::Str(s) => write_string(out, s),
            Json::Arr(a) => {
                out.push('[');
                for (i, v) in a.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    v.write(out);
                }
                out.push(']');
            }
            Json::Obj(m) => {
                out.push('{');
                for (i, (k, v)) in m.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write_string(out, k);
                    out.push(':');
                    v.write(out);
                }
                out.push('}');
            }
        }
    }
}

fn write_string(out: &mut String, s: &str) {
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{08}' => out.push_str("\\b"),
            '\u{0c}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => {
                let _ = write!(out, "\\u{:04x}", c as u32);
            }
            c => out.push(c),
        }
    }
    out.push('"');
}

// ---- decode ----

pub fn parse(s: &str) -> Result<Json, String> {
    let bytes: Vec<char> = s.chars().collect();
    let mut p = Parser { s: bytes, i: 0 };
    p.skip_ws();
    let v = p.value()?;
    p.skip_ws();
    if p.i != p.s.len() {
        return Err("trailing JSON after value".into());
    }
    Ok(v)
}

struct Parser {
    s: Vec<char>,
    i: usize,
}

impl Parser {
    fn peek(&self) -> Result<char, String> {
        self.s.get(self.i).copied().ok_or_else(|| "unexpected end".to_string())
    }
    fn next(&mut self) -> Result<char, String> {
        let c = self.peek()?;
        self.i += 1;
        Ok(c)
    }
    fn skip_ws(&mut self) {
        while self.i < self.s.len() && self.s[self.i].is_whitespace() {
            self.i += 1;
        }
    }
    fn value(&mut self) -> Result<Json, String> {
        self.skip_ws();
        match self.peek()? {
            '{' => self.object(),
            '[' => self.array(),
            '"' => Ok(Json::Str(self.string()?)),
            't' | 'f' => self.boolean(),
            'n' => self.null(),
            _ => self.number(),
        }
    }
    fn object(&mut self) -> Result<Json, String> {
        let mut m = BTreeMap::new();
        self.next()?; // {
        self.skip_ws();
        if self.peek()? == '}' {
            self.next()?;
            return Ok(Json::Obj(m));
        }
        loop {
            self.skip_ws();
            let key = self.string()?;
            self.skip_ws();
            self.expect(':')?;
            let val = self.value()?;
            m.insert(key, val);
            self.skip_ws();
            match self.next()? {
                '}' => return Ok(Json::Obj(m)),
                ',' => continue,
                c => return Err(format!("expected , or }} in object, got {c}")),
            }
        }
    }
    fn array(&mut self) -> Result<Json, String> {
        let mut a = Vec::new();
        self.next()?; // [
        self.skip_ws();
        if self.peek()? == ']' {
            self.next()?;
            return Ok(Json::Arr(a));
        }
        loop {
            a.push(self.value()?);
            self.skip_ws();
            match self.next()? {
                ']' => return Ok(Json::Arr(a)),
                ',' => continue,
                c => return Err(format!("expected , or ] in array, got {c}")),
            }
        }
    }
    fn string(&mut self) -> Result<String, String> {
        self.expect('"')?;
        let mut out = String::new();
        loop {
            let c = self.next()?;
            match c {
                '"' => return Ok(out),
                '\\' => {
                    let e = self.next()?;
                    match e {
                        '"' => out.push('"'),
                        '\\' => out.push('\\'),
                        '/' => out.push('/'),
                        'n' => out.push('\n'),
                        'r' => out.push('\r'),
                        't' => out.push('\t'),
                        'b' => out.push('\u{08}'),
                        'f' => out.push('\u{0c}'),
                        'u' => {
                            let hex: String = (0..4).map(|_| self.next().unwrap_or('0')).collect();
                            let cp = u32::from_str_radix(&hex, 16).map_err(|e| e.to_string())?;
                            out.push(char::from_u32(cp).unwrap_or('\u{fffd}'));
                        }
                        other => return Err(format!("bad escape \\{other}")),
                    }
                }
                c => out.push(c),
            }
        }
    }
    fn boolean(&mut self) -> Result<Json, String> {
        if self.s[self.i..].starts_with(&['t', 'r', 'u', 'e']) {
            self.i += 4;
            Ok(Json::Bool(true))
        } else if self.s[self.i..].starts_with(&['f', 'a', 'l', 's', 'e']) {
            self.i += 5;
            Ok(Json::Bool(false))
        } else {
            Err("bad literal".into())
        }
    }
    fn null(&mut self) -> Result<Json, String> {
        if self.s[self.i..].starts_with(&['n', 'u', 'l', 'l']) {
            self.i += 4;
            Ok(Json::Null)
        } else {
            Err("bad literal".into())
        }
    }
    fn number(&mut self) -> Result<Json, String> {
        let start = self.i;
        while self.i < self.s.len() && "+-0123456789.eE".contains(self.s[self.i]) {
            self.i += 1;
        }
        let num: String = self.s[start..self.i].iter().collect();
        num.parse::<f64>().map(Json::Num).map_err(|e| e.to_string())
    }
    fn expect(&mut self, c: char) -> Result<(), String> {
        let got = self.next()?;
        if got == c {
            Ok(())
        } else {
            Err(format!("expected '{c}', got '{got}'"))
        }
    }
}

// ---- convenience constructors ----
pub fn obj(pairs: Vec<(&str, Json)>) -> Json {
    Json::Obj(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}
pub fn s(v: &str) -> Json {
    Json::Str(v.to_string())
}
pub fn n(v: f64) -> Json {
    Json::Num(v)
}
