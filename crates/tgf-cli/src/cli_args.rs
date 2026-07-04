// SPDX-License-Identifier: AGPL-3.0-or-later
// Shared `--flag value` / `--flag=value` command-line parsing helpers.
//
// Every tgf-cli subcommand hand-rolls its own argument list (no clap
// dependency), so this tiny module is the one place that owns the parsing
// convention shared across `mill_tune` and `mill_puzzle`.

/// Parse a `--flag value` or `--flag=value` pair from an args slice.
pub(crate) fn parse_flag<T: std::str::FromStr>(args: &[String], flag: &str, default: T) -> T {
    let eq_prefix = format!("{flag}=");
    let mut iter = args.iter();
    while let Some(tok) = iter.next() {
        if tok == flag {
            if let Some(val) = iter.next()
                && let Ok(v) = val.parse::<T>()
            {
                return v;
            }
            return default;
        }
        if let Some(val) = tok.strip_prefix(&eq_prefix)
            && let Ok(v) = val.parse::<T>()
        {
            return v;
        }
    }
    default
}

/// Strict variant of [`parse_flag`] for parameters where a silently
/// defaulted value would corrupt an experiment: a MISSING flag falls back
/// to `default`, but a flag that is present with a missing or unparsable
/// value is an `Err` the caller must surface (exit nonzero), never a
/// silent fallback.
pub(crate) fn parse_flag_strict<T: std::str::FromStr>(
    args: &[String],
    flag: &str,
    default: T,
) -> Result<T, String> {
    let eq_prefix = format!("{flag}=");
    let mut iter = args.iter();
    while let Some(tok) = iter.next() {
        if tok == flag {
            let Some(val) = iter.next() else {
                return Err(format!("{flag} requires a value"));
            };
            return val
                .parse::<T>()
                .map_err(|_| format!("{flag} got an invalid value {val:?}"));
        }
        if let Some(val) = tok.strip_prefix(&eq_prefix) {
            return val
                .parse::<T>()
                .map_err(|_| format!("{flag} got an invalid value {val:?}"));
        }
    }
    Ok(default)
}

/// Check whether `--flag` (bare boolean) is present in args.
pub(crate) fn flag_present(args: &[String], flag: &str) -> bool {
    args.iter().any(|a| a == flag)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_flag_reads_space_and_equals_forms() {
        let args = vec!["--db".to_string(), "path/a".to_string()];
        assert_eq!(parse_flag(&args, "--db", String::new()), "path/a");

        let args = vec!["--db=path/b".to_string()];
        assert_eq!(parse_flag(&args, "--db", String::new()), "path/b");
    }

    #[test]
    fn parse_flag_falls_back_to_default_when_absent_or_unparsable() {
        let args = vec!["--other".to_string(), "1".to_string()];
        assert_eq!(parse_flag(&args, "--count", 5usize), 5);

        let args = vec!["--count".to_string(), "not-a-number".to_string()];
        assert_eq!(parse_flag(&args, "--count", 5usize), 5);
    }

    #[test]
    fn flag_present_detects_bare_boolean_flags() {
        let args = vec!["--resume".to_string()];
        assert!(flag_present(&args, "--resume"));
        assert!(!flag_present(&args, "--other"));
    }

    #[test]
    fn parse_flag_strict_falls_back_only_when_the_flag_is_absent() {
        let args = vec!["--other".to_string(), "1".to_string()];
        assert_eq!(parse_flag_strict(&args, "--count", 5usize).unwrap(), 5);

        let args = vec!["--count".to_string(), "7".to_string()];
        assert_eq!(parse_flag_strict(&args, "--count", 5usize).unwrap(), 7);

        let args = vec!["--count=9".to_string()];
        assert_eq!(parse_flag_strict(&args, "--count", 5usize).unwrap(), 9);
    }

    #[test]
    fn parse_flag_strict_rejects_present_but_unusable_values() {
        // Malformed value.
        let args = vec!["--count".to_string(), "abc".to_string()];
        assert!(parse_flag_strict(&args, "--count", 5usize).is_err());
        // Flag at the end of the argument list: no value at all.
        let args = vec!["--count".to_string()];
        assert!(parse_flag_strict(&args, "--count", 5usize).is_err());
        // Equals form with an empty value.
        let args = vec!["--count=".to_string()];
        assert!(parse_flag_strict(&args, "--count", 5usize).is_err());
        // Out of the target type's range (negative into an unsigned).
        let args = vec!["--count".to_string(), "-1".to_string()];
        assert!(parse_flag_strict(&args, "--count", 5usize).is_err());
        // The "value" is actually the next flag.
        let args = vec!["--count".to_string(), "--other".to_string()];
        assert!(parse_flag_strict(&args, "--count", 5usize).is_err());
    }
}
