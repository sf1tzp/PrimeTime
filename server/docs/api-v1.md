<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
<!-- Copyright (C) 2026 Steven Fitzpatrick -->

# PrimeTime API v1

The PrimeTime server speaks GraphQL on `POST /graphql`. This document
describes the v1 contract — the first PrimeTime-owned schema, no longer
traggo-compatible. The full schema is [`../schema.graphql`](../schema.graphql);
this page covers the concepts and the operations a client needs.

## Vocabulary

- **Label** — a `key: value` dimension attached to a timespan
  (e.g. `repo: primetime`, `type: review`). The Prometheus mental model:
  time series with dimensions.
- **Label definition** — registers a key for a user: the key plus its
  display colour and any per-value colour overrides. A key must be defined
  before it can appear on a timespan.
- **Label set** — a named, ordered, launchable combination of labels with an
  SF Symbol icon (the launcher cards in the mac app).

Label keys are lower-case and contain no spaces; the server rejects
anything else at definition time.

## Authentication

Unchanged in shape from the traggo lineage: `login(username, pass,
deviceName, type, cookie)` returns a device token, sent on subsequent
requests as `Authorization: traggo <token>`. Device management
(`devices`, `createDevice`, `updateDevice`, `removeDevice`,
`removeCurrentDevice`) and user administration (`users`, `createUser`,
`updateUser`, `removeUser` — admin only) are unchanged. A GraphQL
playground is served on `GET /graphql` for browsers.

## Label definitions and colours

```graphql
type LabelDefinition {
    key: String!
    color: String!                     # the key colour (hex, e.g. "#2196f3")
    valueColors: [LabelValueColor!]!   # per-value overrides, sorted by value
    usages: Int!                       # how many of the user's timespans use the key
}
type LabelValueColor { value: String!, color: String! }
```

Queries:

- `labelDefinitions: [LabelDefinition!]` — all of the current user's
  definitions, most-used first.
- `suggestLabelKey(query): [LabelDefinition!]` — prefix search on keys.
- `suggestLabelValue(key, query): [String!]` — values previously used with
  the key (substring match, max 10).

Mutations:

- `createLabelDefinition(key, color)` / `updateLabelDefinition(key, newKey,
  color)` / `removeLabelDefinition(key)` — key CRUD. Renaming a key
  rewrites it on the user's timespans, dashboard entries, and value-colour
  rows; removing deletes its timespan labels and value colours.
- `setLabelValueColor(key, value, color)` — set or replace the colour
  override for one value of a key. Returns the updated definition.
- `clearLabelValueColor(key, value)` — remove the override; the value falls
  back to the key colour.

Value colours are per user, per key, per value — the server-side
replacement for the mac app's local `valueColors` overlay.

## Label sets

```graphql
type LabelSet {
    id: Int!
    name: String!
    symbolName: String!    # SF Symbol for the launcher card
    labels: [Label!]!      # ordered members
}
```

- `labelSets: [LabelSet!]` — the current user's sets in launcher order.
- `createLabelSet(name, symbolName, labels)` — appends to the launcher
  order. Member order is the input order.
- `updateLabelSet(id, name, symbolName, labels)` — replaces name, symbol,
  and members wholesale.
- `moveLabelSet(id, position)` — move a set to a 0-based position
  (clamped); returns all sets in their new order.
- `removeLabelSet(id)` — deletes the set and its members.

Set members are *not* required to reference existing label definitions —
sets are launcher conveniences; definitions are enforced where labels
attach to timespans.

### The default collection

The server keeps a collection of template label sets (no owner, flagged
`default_collection`). When a user is created — via the `createUser`
mutation, the admin CLI, or the fresh-database default admin — the
collection is copied to them, and a label definition (colour
`#2196f3`) is created for every referenced key they don't already have.
The collection is managed with the admin CLI:

```sh
admin add-default-set -name "Deep Work" -symbol brain.head.profile -labels "type=programming"
admin list-default-sets
admin remove-default-set -id 3
admin seed-user -name someone     # apply the collection to an existing (unseeded) user
```

## Timespans

Timespan shapes and paging are structurally unchanged from the traggo
lineage; the wire now says `labels`:

- `timeSpans(fromInclusive, toInclusive, cursor): PagedTimeSpans!` —
  finished timespans, newest first, stable-cursor paging.
- `timers: [TimeSpan!]` — running timespans (`end == null`).
- `createTimeSpan(start, end, labels, note)`, `updateTimeSpan(id, start,
  end, labels, oldStart, note)`, `stopTimeSpan(id, end)`,
  `copyTimeSpan(id, start, end)`, `removeTimeSpan(id)`.
- `replaceTimeSpanLabels(from, to, opt)` — bulk-rewrite one label
  (key *and* value) across the user's history.

Every label on a timespan must have a defined key (`createLabelDefinition`
first). `Time` values are RFC3339.

## Statistics

`stats(ranges, keys, excludeLabels, requireLabels)` and `stats2(now,
stats)` aggregate time per `key: value` over ranges — the core
aggregations, and the natural backbone of any future web UI.
`InputStatsSelection` uses `keys` / `excludeLabels` / `includeLabels` and a
required `range` (static timestamps or relative expressions like
`now-1d/d`); weeks run Monday through Sunday.

Traggo's dashboards (dashboard/entry/range CRUD and their types) and
`userSettings` (theme, date locale, week start, input style) are **not**
part of v1: PrimeTime is opinionated — stats views belong to the client,
and those settings were web-UI-shaped with no PrimeTime consumer.

## User preferences

The minimal per-user client state a second device should inherit.
Colouring *data* (key and value colours) already syncs via
`LabelDefinition`; these two preferences are what remains:

```graphql
type UserPreferences {
    colorByValue: Boolean!      # colour timespans by label value
    menuLabelSetLimit: Int!     # how many label sets the menu shows (0 = all)
}
```

- `userPreferences: UserPreferences!` — the current user's preferences;
  fresh-user defaults are `colorByValue = true` (value-based colouring is
  PrimeTime's default behaviour — key colours remain for navigating Label
  Review) and `menuLabelSetLimit = 5`.
- `setUserPreferences(preferences: InputUserPreferences!)` — replaces both
  values.

## Renames from the traggo wire (for importers)

| traggo (pre-v1)             | PrimeTime v1                          |
|-----------------------------|---------------------------------------|
| `tags` query                | `labelDefinitions`                    |
| `TagDefinition`             | `LabelDefinition` (+ `valueColors`, − `user`) |
| `createTag` / `updateTag` / `removeTag` | `createLabelDefinition` / `updateLabelDefinition` / `removeLabelDefinition` |
| `suggestTag` / `suggestTagValue` | `suggestLabelKey` / `suggestLabelValue` |
| `TimeSpanTag` / `InputTimeSpanTag` | `Label` / `InputLabel`          |
| `TimeSpan.tags`, `tags:` args | `TimeSpan.labels`, `labels:` args   |
| `replaceTimeSpanTags`       | `replaceTimeSpanLabels`               |
| `stats(…, tags, excludeTags, requireTags)` | `stats(…, keys, excludeLabels, requireLabels)` |
| `StatsSelection.tags/excludeTags/includeTags` | `InputStatsSelection.keys/excludeLabels/includeLabels` (`rangeId` dropped, `range` now required) |
| `dashboards` + dashboard/entry/range CRUD and types | *dropped*       |
| `userSettings` / `setUserSettings` + `Theme`/`DateLocale`/`WeekDay`/`DateTimeInputStyle` | *dropped* |
| —                           | `userPreferences` / `setUserPreferences` |
| —                           | `labelSets` + label-set mutations     |
| —                           | `setLabelValueColor` / `clearLabelValueColor` |

`StatInput`, `DashboardSize` (unused upstream), and the output-side
`StatsSelection` / `RelativeOrStaticRange` types were dropped as well.
