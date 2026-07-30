# PaneCue v0.2 Dialogue Benchmark

Status: **runner implemented; five-author corpus collection pending**

The frozen evaluation corpus is private, human-authored, and independent from
all PaneCue training data. Its text must live outside the repository. PaneCue
commits only the schema, evaluator, aggregate metrics, and opaque failing record
identifiers.

## Required corpus

The external directory contains:

- `manifest.json` — frozen corpus declaration and pseudonymous authors;
- `records.jsonl` — one independently authored evaluation record per line.

The runner rejects a corpus unless it contains at least:

- 200 Russian command records;
- 200 English command records;
- 100 contextual follow-up records;
- 200 combined no-action, negation, and ambiguity records;
- contributions from five declared human authors.

At least 100 follow-ups must carry an expected referent. The safety set must
contain both no-action and ambiguous examples so neither safety gate can pass
vacuously.

Every author declaration must set `human_authored` and
`consent_to_evaluation` to `true`. The manifest must set `frozen` and
`training_use_prohibited` to `true`. Author IDs and record IDs are opaque and
must contain only letters, digits, `.`, `_`, or `-`.

## Manifest contract

```json
{
  "schema_version": 1,
  "corpus_id": "opaque-corpus-id",
  "frozen": true,
  "training_use_prohibited": true,
  "authors": [
    {
      "id": "author-01",
      "human_authored": true,
      "consent_to_evaluation": true
    }
  ]
}
```

Five author declarations are required. Do not add names, email addresses, or
other personal data.

## Record contract

Each JSONL object contains:

- `schema_version`: `1`;
- `id`: opaque unique record ID;
- `author_id`: one declared author ID;
- `locale`: `ru` or `en`;
- `category`: `command`, `follow_up`, `no_action`, or `ambiguous`;
- `utterance`: private human-authored evaluation input;
- `context_utterance`: required only for `follow_up`;
- `expected.operation`: the expected semantic operation;
- `expected.referent`: required for every `follow_up`;
- `expected.targets`: ordered target keys for a plan command;
- `expected.selection_id`: opaque candidate ID required for `ambiguous`;
- `inventory`: privacy-safe candidate metadata for `ambiguous`.

Target keys use `application:<bundle-identifier>` or `role:<role>`. Allowed
operations are:

`create_plan`, `direct_action`, `add_window`, `remove_window`,
`resize_window`, `move_window`, `swap_windows`, `undo`, `save`, `no_action`,
and `needs_selection`.

The ambiguity gate first requires Preview to expose a choice and then selects
`expected.selection_id`; the case passes only when that exact candidate is
resolved without a remaining ambiguous slot. Ambiguity inventory must contain
only opaque candidate IDs, bundle
identifiers, generic application names, roles, display assignment, and window
capability flags. Window titles, document paths, URLs, transcripts, and user
content are forbidden.

## Independence and privacy

- The corpus directory must resolve outside the git repository.
- The runner rejects normalized duplicates and exact overlap with all current
  training, hard-data, and challenge inputs.
- Corpus text is never used by a training script or copied into a test fixture.
- Output contains aggregate metrics and opaque record IDs only.
- Failed inputs are corrected in product code; they are not copied into
  training data before the v0.2 test set is retired.

## Frozen gates

- command accuracy ≥95%;
- contextual delta-operation accuracy ≥95%;
- pronoun/referent accuracy ≥90%;
- ambiguity exposed and resolved 100%;
- follow-up isolation 100%;
- zero dangerous actions on no-action cases.

Run the gate with:

```sh
./scripts/run_dialogue_benchmark.sh /absolute/external/corpus-directory
```

The command exits non-zero for invalid provenance, insufficient counts,
training overlap, malformed records, or a failed metric. The final aggregate
JSON may be attached to release evidence after verifying that it contains no
corpus text or filesystem paths.
