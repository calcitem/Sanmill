**Perfect Database Compression Assessment**

*Evidence-based recommendation for specialist review of a Nine Men's Morris Perfect DB*

**Purpose:** Assess whether the 83.58 GB Perfect DB can be reduced to 7 GB or below without materially weakening MTD(f)/PVS play.

**Status:** Revised technical assessment incorporating external Mill expert feedback.

**Evidence:** Full-sector conversion and verification, Android ARM64 cross-build, and Pixel 7 timing experiments.

**Scope:** Standard Ultra-strong 1.1.0 database; other variants require a separately matched database. Deliberately random move selection is out of scope.

| **Executive conclusion.** The 7 GB target is comfortably achievable without heuristic pruning. The recommended product decision is to make two user-selectable downloads available: Exact WDL, a 2-bit zstd database of 2.103 GB that preserves full game-theoretic selection quality; and Compact Safety, a 1-bit XZ database of 0.992 GB that prevents an avoidable first losing complete turn but may downgrade a theoretical win to a draw. The Mill expert regarded the safety-only contract, both-package choice and roughly 2.3-second cold load as acceptable. These product judgements do not prove rule compatibility: release must remain blocked until the database conventions match the active Sanmill rules exactly and a runtime ruleset fingerprint enforces that match. |
|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

# 1. Decision recommendation

No layer deletion, material-based pruning, HumanDB-only selection, or differential reordering is required to meet the size target. Those alternatives either weaken the safety guarantee or offer negligible additional compression.

-   Exact WDL package: retain exact W/D/L information using the 2-bit zstd profile. At 2.103 GB it is already 96% below the 83.58 GB source and remains well below the 7 GB requirement. This is the strength-preserving choice.
-   Compact Safety package: retain the complete 1-bit safety plane using whole-sector XZ. Full packaging reached 0.992 GB. It prevents an avoidable first loss, subject to exact ruleset compatibility, but the largest cold sector requires approximately 2.3-2.5 seconds of CPU decompression on a Pixel 7.
-   Keep the 1.096 GB 1-bit zstd profile as a low-latency packaging alternative if product testing favours faster cold access over the additional 104 MB saving offered by XZ. It has the same safety semantics, not the full strength of Exact WDL.
-   Do not infer a win from material advantage. Every safety decision must use exact successor W/D/L data after the entire logical turn, including compulsory removal after forming a mill.
-   Fail closed on ruleset mismatch: if the active rules cannot be proven identical to the database manifest, disable Perfect DB correction and leave the conventional search result authoritative.

# 2. Disposition of Mill expert feedback

The replies below are relevant to this compression assessment. They establish terminology and product acceptability; they do not independently validate the database generator, Sanmill implementation or measured engineering results.

| **Topic**             | **Expert position**                                                                                                  | **Disposition in this assessment**                                                                                                         |
|-----------------------|----------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Complete logical turn | Include the primary action and compulsory removal.                                                                   | Adopted as the safety-decision boundary.                                                                                                   |
| Safety-only guarantee | Acceptable and likely to support product uptake.                                                                     | Adopted as the contract of Compact Safety, with the win-to-draw limitation stated explicitly.                                              |
| Package choice        | Make both exact 2-bit and 1-bit options available.                                                                   | Adopted as the recommended product offering: Exact WDL and Compact Safety.                                                                 |
| Cold XZ delay         | Approximately 2.3 seconds is acceptable.                                                                             | Adopted subject to background decoding, caching and visible progress if the data is not ready.                                             |
| Rule compatibility    | No confirmation that database and live rules match.                                                                  | Unresolved release gate; engineering evidence is required before enabling either package.                                                  |
| Ruleset variants      | Standard German, Hungarian and English rules are central; Sanmill may retain further variants such as Russian rules. | A database may serve only an exactly matched ruleset. Other variants require their own validated database or conventional-search fallback. |

# 3. Scope, objective and terminology

The assessed database contains 512 files totalling 83,582,223,577 bytes. The 498 standard .sec2 sectors account for 83,582,099,742 bytes; the remaining metadata is negligible for the proposed formats. The objective is a package of approximately 7 GB or smaller while keeping the additional root-level database correction delay within an acceptable practical bound.

The application currently searches first using conventional algorithms such as MTD(f) and PVS, then lets the Perfect DB correct the root decision. The analysis therefore targets root-level correction, not a database lookup at every search node. Production move ordering with shuffling enabled was represented in the search-risk tests. Deliberately random move selection is not a design target.

In this report, W, D and L are exact outcomes from the side-to-move perspective of the stored successor position. A 'complete logical turn' means a placement or move plus the compulsory capture/removal where applicable.

# 4. What the 1-bit safety plane preserves and loses

The aggressive profile stores only one exact predicate per position: whether the side to move is game-theoretically winning. For a candidate complete turn from the current position to a successor, the candidate is losing for the current player exactly when the successor is W for the opponent.

| **Exact successor result (opponent to move)** | **Stored bit** | **Meaning for the candidate**                       | **Required action**                  |
|-----------------------------------------------|----------------|-----------------------------------------------------|--------------------------------------|
| W                                             | 1              | The opponent has a forced win; the candidate loses. | Reject if any safe candidate exists. |
| D                                             | 0              | The candidate preserves a draw.                     | Safe.                                |
| L                                             | 0              | The current player has a forced win.                | Safe.                                |

| **Safety boundary.** A 1-bit table cannot distinguish a draw from a win. It can therefore downgrade a winning position to a draw if the conventional search selects the drawing safe move. It cannot, however, select a losing move while a non-losing complete turn exists, provided the exact database applies to the current rule context. |
|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

This is a semantic reduction, not a heuristic estimate. It is resistant to human tactical traps in flying positions because no material threshold, static evaluation, opening frequency, or HumanDB popularity is used. A forced-loss root cannot be repaired because all legal successors are W for the opponent.

The reader must evaluate terminal states, repetition policy and any move-count draw rule before using the bit. It must also query after compulsory removal rather than treating a mill-forming intermediate state as a complete candidate.

# 5. Data conversion and correctness evidence

Two dense encodings were generated from all 498 standard sectors: a 2-bit exact W/D/L plane and a 1-bit W predicate plane. The 2-bit source contains 6,965,178,695 packed bytes; the 1-bit source contains 3,482,592,697 packed bytes.

-   The complete 1-bit output was checked byte-for-byte against all source sectors: 498 files, 3,482,592,697 bytes, 53,443 smaller chunks and 1,225 4 MB chunks; no mismatch was observed.
-   The complete 2-bit conversion was checked across all 498 sectors; representative exact database queries across placing, moving and flying states produced no mismatch.
-   The full XZ package contains 498 streams and passed parallel xz stream-integrity tests after generation.

The conversion is complete coverage, not a selected endgame book. This distinction is essential: retaining every exact successor is what makes the 1-bit no-first-loss rule independent of human opening frequency and resistant to unforeseen traps.

# 6. Full-size results

| **Profile**                          | **Exact information retained** | **Full payload**           | **Compression result**                                              |
|--------------------------------------|--------------------------------|----------------------------|---------------------------------------------------------------------|
| 2-bit W/D/L + zstd, 64 KB, level 1   | W, D and L                     | 2,102,791,559 B (2.103 GB) | Exact baseline; 96% below the source.                               |
| 1-bit safety + zstd, 64 KB, level 1  | Opponent-W predicate only      | 1,213,669,869 B (1.214 GB) | Fast small-block safety profile.                                    |
| 1-bit safety + zstd, 4 MB, level 19  | Opponent-W predicate only      | 1,095,864,716 B (1.096 GB) | Fully verified; compact and responsive.                             |
| 1-bit safety + XZ, whole sector, -9e | Opponent-W predicate only      | 992,205,020 B (0.992 GB)   | Full package built and integrity-tested; 84.2x smaller than source. |

XZ saves 103,659,696 bytes (9.46%) relative to the 1-bit zstd 4 MB/level 19 package. It does not change the semantic trade-off: both 1-bit profiles prevent an avoidable first loss but may sacrifice a win in favour of a draw.

GB is decimal in this report. The XZ result is 0.924 GiB. A small manifest, sector identifiers and integrity metadata would add far less than 1 MB.

# 7. Pixel 7 performance and native integration

All mobile figures below were measured with an Android ARM64 native probe on the connected Pixel 7. The compressed test file was resident in the operating-system file cache, so the figures primarily measure decoder CPU time; a truly cold storage read may add latency.

| **Profile / block**          | **Largest-sector observation**                                                                                     | **Decoded-cache behaviour**                                                                                                                  | **Practical interpretation**                                                                                          |
|------------------------------|--------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| 2-bit zstd, 64 KB, level 1   | Cold random byte lookup: p50 about 104 microseconds; p99 about 135 microseconds.                                   | Small decoded blocks are inexpensive to retain.                                                                                              | Best response-time and exact-strength profile.                                                                        |
| 1-bit zstd, 4 MB, level 19   | Cold block: p50 about 10 ms. Decoding all 18 blocks of the 75 MB maximum sector: about 180 ms.                     | A warm cached lookup is sub-microsecond. Two target sectors imply roughly 360 ms decoder work in the conservative case.                      | Strong option when safety-only semantics are acceptable.                                                              |
| 1-bit XZ, whole 75 MB sector | Repeated maximum-sector decodes: about 2.28-2.54 s. Same-sector -6e runs were about 2.28 s; -9e about 2.49-2.54 s. | After a full sector is cached, lookups are effectively free. A root correction may need two successor sectors in a capture/no-capture split. | Technically acceptable only if a first-miss delay of about 2.3 s, and an exceptional two-sector delay, is acceptable. |

For the same 75 MB sector, XZ -6e produced 46,864,588 bytes and XZ -9e produced 46,726,636 bytes: only a 0.3% size difference. The -6e decoder showed about 11 MB resident memory during the probe versus about 34 MB for -9e, and it was consistently faster. If XZ is selected, -6e is the better engineering candidate; a full -6e package should be generated before release to confirm the small sample-based size delta.

Native integration is not a blocking concern. An Android API 23 ARM64 static build of xzdec was 359,208 bytes; the unstripped static liblzma archive was 1,716,526 bytes. The test executable depended only on Android system libc, libm and libdl, not on a separately shipped XZ shared library. Production builds should pin an audited upstream source revision and retain reproducible build records.

# 8. Alternatives assessed

| **Alternative**                         | **Evidence**                                                                                                                                                                                            | **Assessment**                                                                                                          |
|-----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|
| Omit database layers and rely on search | With production-style shuffling, DB-free MTD(f) selected an exact losing move despite an available non-losing alternative in sampled tests: 1% at 8v8 moving/depth 8 and 5% at 8v8 placing 1,1/depth 8. | Not suitable for a no-first-loss promise. The figures demonstrate counterexamples, not a human-play frequency estimate. |
| Material-advantage pruning              | Flying-stage positions can reverse apparent material superiority.                                                                                                                                       | Rejected. Exact outcome must replace material inference.                                                                |
| Cross-layer XOR or difference coding    | A tested 8v8 cross-hand XOR chain was 9.2% larger than direct planes. Bit-transition delta improved the maximum-sector zstd result by only 0.026%.                                                      | No product-level benefit.                                                                                               |
| Reorder positions before compression    | Transpose and tested tilings were equal to or worse than the existing combinatorial hash order.                                                                                                         | The present order already has useful locality for zstd.                                                                 |
| HumanDB as a replacement                | The top 500,000 train positions covered only 48.02% of held-out HumanDB visits.                                                                                                                         | Useful for pre-warming or prioritisation, not for complete safety coverage.                                             |

A Brotli quality-11 maximum-sector sample was smaller than zstd but larger than XZ (44.13 MB versus 43.06 MB) and decoded in about 0.84-0.85 s on the Pixel 7. It is a possible intermediate future profile, but no full Brotli package was built, so it is not a release recommendation in this assessment.

# 9. Recommended reader behaviour

1.  Run the normal MTD(f)/PVS search with the existing production move-order behaviour.
2.  For the selected root move, query the exact successor safety bit after the entire logical turn. If the successor is not W for the opponent, retain the search choice.
3.  Only if the selected move is exactly losing, enumerate the legal complete turns, group them by target sector for cache locality, and reject all whose successor is W for the opponent.
4.  If at least one safe turn exists, choose a safe candidate using the existing search ordering or a constrained second root search. Never select randomly merely because the one-bit data cannot distinguish win from draw.
5.  If all candidates are losing, preserve the conventional search result because the root is exact forced loss. Apply terminal, repetition and rule-context checks before every Perfect DB correction.

For a zstd profile, the reader should use a bounded LRU of independently compressed blocks. For a whole-sector XZ profile, it should decode off the UI thread, cache the complete bitplane, and order the fallback scan by sector to avoid cache thrashing.

To hide XZ cold-load latency, begin asynchronous pre-warming as soon as iterative search identifies a provisional root move and therefore a likely successor sector; prefetch the capture/no-capture counterpart when applicable while MTD(f)/PVS continues. If search finishes before the required sector is ready, show non-blocking progress, for example a spinning Mill board, until correction completes. Measure this pipeline on-device because the benefit depends on search duration and cache state.

# 10. Ruleset fingerprint and unresolved release gate

| **Release gate.** Neither Exact WDL nor Compact Safety should correct a move until the Standard Ultra-strong database conventions have been shown to match the active Sanmill rules. The expert response explicitly leaves this question unresolved. |
|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|

Each package should carry a signed or integrity-protected manifest containing at least: game and board topology; named ruleset/variant; piece count and placement rules; flying conditions; terminal conditions; repetition and move-count draw policies; mill and removal conventions; W/D/L perspective; database generation and schema version; index/canonicalisation version; semantic profile (Exact WDL or Compact Safety); codec parameters; sector inventory; and payload checksums.

At runtime, Sanmill should construct the same fingerprint from the active configuration and compare it exactly with the manifest. Any mismatch, unknown field, unsupported variant, missing sector, version disagreement or integrity failure must disable database correction. German, Hungarian, English and Russian labels must not be treated as interchangeable merely because they share the same board.

Release evidence should include rule-by-rule generator/runtime comparison, terminal and removal edge-case fixtures, repetition and move-count draw fixtures, placing/moving/flying query parity, manifest mismatch tests, corruption tests and a device test proving that fallback conventional search remains functional when the database is rejected.

# Appendix A. Traceability and evidence notes

Dataset: Malom Standard Ultra-strong 1.1.0, standard sectors. Compression experiments used a dedicated temporary experiment directory and did not alter the original database. The one-bit source was generated from exact W/D/L values, not from engine evaluation or HumanDB samples.

Validation: full packed-byte verification of the 1-bit source, full-stream XZ integrity testing, representative exact query validation across placing/moving/flying states, storage-size accounting across all 498 sectors, and native Android measurements on a Pixel 7.

External codec reference: Tukaani Project, XZ Utils, https://tukaani.org/xz/. The Android proof-of-concept used a current audited upstream source build for the native decoder. All quoted performance figures are engineering measurements, not guarantees under every thermal, storage or operating-system condition.
