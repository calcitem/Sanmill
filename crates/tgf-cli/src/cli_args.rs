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
}
