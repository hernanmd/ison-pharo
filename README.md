[![license-badge](https://img.shields.io/badge/license-MIT-blue.svg)](https://img.shields.io/badge/license-MIT-blue.svg)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
[![Project Status: Active](http://www.repostatus.org/badges/latest/active.svg)](http://www.repostatus.org/#active)

# ISON for Pharo

A compact, token-efficient, line-oriented text format for serializing structured data and
property graphs, with a lossless reader/writer, a canonical/deterministic encoder, a configurable
edge-row contract, and a budget-aware context packer — all in pure Pharo, with no external
dependencies.

# Table of Contents

- [Description](#description)
- [Why ISON](#why-ison)
- [Installation](#installation)
  - [Baseline string](#baseline-string)
- [Quick start](#quick-start)
- [The format](#the-format)
  - [Blocks](#blocks)
  - [Scalars and quoting](#scalars-and-quoting)
  - [Nested objects: dotted columns](#nested-objects-dotted-columns)
  - [Lists and tables: child blocks](#lists-and-tables-child-blocks)
  - [Interned file / long-string table](#interned-file--long-string-table)
  - [Graph layout: nodes and edges](#graph-layout-nodes-and-edges)
- [The edge-row contract (schema)](#the-edge-row-contract-schema)
- [Node and reference ids](#node-and-reference-ids)
- [Writing](#writing)
- [Reading](#reading)
- [Lossless round-trips and equivalence](#lossless-round-trips-and-equivalence)
- [Canonical, deterministic output](#canonical-deterministic-output)
- [The context packer](#the-context-packer)
- [The token estimator](#the-token-estimator)
- [Class reference](#class-reference)
- [Specializing for your own data](#specializing-for-your-own-data)
- [Contribute](#contribute)
- [License](#license)

# Description

ISON encodes a JSON-shaped value (dictionaries, arrays, scalars) as a small set of
**newline-delimited, columnar blocks**. A column header is written once and shared by every row
beneath it, so repetitive structured data — and especially property graphs — serialize to far fewer
characters (and fewer LLM tokens) than pretty-printed or minified JSON, while remaining human
readable and losslessly reversible.

The library is a single package, `ISON-Core`, with no dependencies beyond a base Pharo image. It
provides:

- **`IsonGraphWriter`** — serialize any JSON-shaped object to ISON text.
- **`IsonGraphReader`** — parse ISON text back to the equivalent object.
- **`IsonGraphCodec`** — the scalar/normalization/quoting rules and a structural-equivalence test.
- **`IsonGraphEdgeRowSchema`** — a configurable contract naming how *reference rows* identify an
  edge's endpoints and type, so the graph layout is not tied to any particular field vocabulary.
- **`IsonGraphContextPacker`** — fit the largest prefix of a prioritized node set into a token
  budget, producing one pinned, digest-stamped document.
- **`IsonGraphTokenEstimator`** — a cheap, dependency-free, deliberately conservative token estimate.

# Why ISON

A property graph in formatted JSON repeats every field name on every object:

```json
{
  "nodes": [
    { "id": 1, "type": "person", "name": "Alice", "age": 30 },
    { "id": 2, "type": "person", "name": "Bob",   "age": 25 }
  ],
  "edges": [
    { "source": 1, "target": 2, "relation": "knows", "since": 2020 }
  ]
}
```

ISON writes each field name once, as a column header:

```
edges.knows
since source target
2020 :person:1 :person:2

nodes.person
id age name
1 30 Alice
2 25 Bob
```

The saving grows with the number of rows. ISON is at its best for data that is **serialized once and
read many times** — reference material placed in an LLM context window, cached prompt prefixes,
content-addressed snapshots.

# Installation

```smalltalk
EpMonitor disableDuring: [
    Metacello new
        baseline: 'ISONCore';
        repository: 'github://hernanmd/ison-pharo/src';
        load ].
```

## Baseline string

To depend on ISON from your own Metacello baseline:

```smalltalk
spec
    baseline: 'ISONCore'
    with: [ spec repository: 'github://hernanmd/ison-pharo/src' ].
```

Then add `'ISONCore'` to the `requires:` of any package that uses it.

# Quick start

```smalltalk
"Serialize a nested object"
| text |
text := IsonGraphWriter new documentFor: (Dictionary new
    at: 'name'   put: 'alice';
    at: 'age'    put: 30;
    at: 'active' put: true;
    at: 'tags'   put: #( 'a' 'b' );
    at: 'profile' put: (Dictionary new at: 'city' put: 'NYC'; at: 'zip' put: '10001'; yourself);
    yourself).

"Parse it back"
| value |
value := IsonGraphReader new read: text.

"They are equivalent under ISON's normalization"
IsonGraphCodec equivalent:
    (Dictionary new at: 'name' put: 'alice'; yourself)
    to: (IsonGraphReader new read: (IsonGraphWriter new documentFor:
        (Dictionary new at: 'name' put: 'alice'; yourself)))   "=> true"
```

The object above serializes to:

```
# ison1
meta.result
name active age profile.city profile.zip tags:list
alice true 30 NYC "10001" 2

list.result-tags
v
a
b
```

# The format

An ISON document is a sequence of **blocks** separated by blank lines. The first line is the format
marker `# ison1` (any line starting with `#` is a comment). The top-level value lives in a block
named `meta.result`.

## Blocks

Each block has:

1. a header line `kind.name` (e.g. `meta.result`, `nodes.person`, `list.result-tags`);
2. a **field line** listing the column names once;
3. one **row** per line, cells separated by single spaces.

A cell of `~` is null. Fields may carry a type hint as `name:hint` (see the sections below for
`:list`, `:tab`, `:obj`, `:json`, `:file`, `:nodes`, `:refs`).

## Scalars and quoting

| Type    | Example                         |
|---------|---------------------------------|
| String  | `alice` or `"alice smith"`      |
| Integer | `42`, `-7`                      |
| Float   | `3.14`                          |
| Boolean | `true` / `false`                |
| Null    | `~`                             |

A value is double-quoted when it would otherwise be ambiguous — it contains whitespace, a quote, a
backslash or a control character; it starts with `#` or `:`; it looks like a number, a boolean or a
null; or it would be read as a block header. Quoting is applied automatically by the writer and
undone by the reader, so round-trips preserve the original string exactly (e.g. the string `"10001"`
above is quoted so it is read back as a string, not the integer `10001`).

## Nested objects: dotted columns

An object whose values are scalars (to any depth) is flattened into dotted-path columns, so
`profile.city` and `profile.zip` in the Quick-start output are the nested `profile` object. Objects
that nest arrays cannot flatten; they become a child block instead (`:obj` / `:tab`, below).

## Lists and tables: child blocks

An array in a cell is written as a **count** in the parent row plus a child block:

- an array of scalars → a `list.<path>` block with a single column `v`;
- an array of objects → a `tab.<path>` block, one row per element.

When the parent block has more than one row, each child row carries an `r` column holding the
0-based index of its parent row, so the association is unambiguous.

```
# ison1
meta.result
tags:list
2

list.result-tags
v
a
b
```

## Interned file / long-string table

Long, highly repeated string values under keys named `file` or `filePath` are interned into a
shared `list.files` table and referenced by index (a `:file` column holds the 0-based index). This
keeps a repeated path from being written on every row.

## Graph layout: nodes and edges

A top-level result that is a set of **node rows** or **reference (edge) rows** gets a graph layout:

- node rows (each with an `id` and a `kind`) become `nodes.<Kind>` blocks — the kind travels in the
  block name, not in every row;
- reference rows become `edges.<edgeType>` blocks whose `source` and `target` cells are `:Kind:id`
  references; an endpoint attribute that is consistent for a given node (e.g. its `name`) is written
  **once** on that node's `nodes.<Kind>` row rather than repeated on every edge.

```
# ison1
meta.result
resultKind results:refs+targetName
reference 1

nodes.person
id name
"1" ~
"2" Bob

edges.knows
source target
:person:1 :person:2
```

The `results:refs+targetName` hint records which endpoint attributes were lifted onto the node rows,
so the reader can put them back on the edges.

# The edge-row contract (schema)

Which keys in a reference row name the edge's source id, source kind, target id, target kind, edge
type, and endpoint-attribute prefixes is **configurable** via `IsonGraphEdgeRowSchema`. The default
contract is neutral:

| Role                 | Default key / prefix |
|----------------------|----------------------|
| source id            | `source`             |
| source kind          | `sourceKind`         |
| target id            | `target`             |
| target kind          | `targetKind`         |
| edge type            | `edgeType`           |
| source attr. prefix  | `source` (e.g. `sourceName`)   |
| target attr. prefix  | `target` (e.g. `targetCitation`) |

So a reference row is a dictionary like:

```smalltalk
Dictionary new
    at: 'source'     put: '1';
    at: 'sourceKind' put: 'person';
    at: 'edgeType'   put: 'knows';
    at: 'target'     put: '2';
    at: 'targetKind' put: 'person';
    at: 'targetName' put: 'Bob';   "an endpoint attribute, lifted onto target node 2"
    yourself
```

If your data uses different field names, supply your own schema (see
[Specializing for your own data](#specializing-for-your-own-data)). The writer and reader must use
the **same** schema, because the schema's key names are how reference rows are recognized on the way
out and rebuilt on the way in.

# Node and reference ids

A node reference is written `:<kind>:<id>` (e.g. `:person:1`). Ids may contain characters that the
`:kind:id` syntax cannot carry verbatim, so ids inside graph blocks are percent-encoded:

- **readable** mode (default): only whitespace, control characters and `%` are escaped, so ids stay
  legible (`a b/c:d` → `a%20b/c:d`);
- **strict** mode (`strictGraphIds: true`): also escapes `:`, `|`, `"` and backslash, producing ids
  that load into strict reference-graph readers (`a b/c:d` → `a%20b/c%3Ad`).

The reader decodes both. Choose strict only when a downstream consumer needs it; it costs a few more
characters.

# Writing

```smalltalk
IsonGraphWriter new documentFor: anObject.                    "readable ids (default)"
IsonGraphWriter new strictGraphIds: true; documentFor: anObject.  "strict ids"
IsonGraphWriter new edgeRowSchema: aSchema; documentFor: anObject. "custom edge-row contract"
```

`documentFor:` accepts any JSON-shaped object — a `Dictionary`, an `Array`, or a scalar. A top-level
value that is not a dictionary is wrapped (the marker line carries ` wrapped`), so arrays and scalars
round-trip too.

# Reading

```smalltalk
IsonGraphReader new read: isonText.                        "neutral edge-row contract"
IsonGraphReader new edgeRowSchema: aSchema; read: isonText. "custom contract (match the writer)"
```

`read:` returns the normalized object the document encodes. A truncated document (a child block whose
row count does not match its parent's count cell) raises an error rather than returning a partial
result.

# Lossless round-trips and equivalence

ISON is lossless under a stated **normalization**, checked with `IsonGraphCodec equivalent:to:`:

- a nil-valued key equals an absent key;
- an object with no non-nil entries equals nil;
- `Symbol`s compare equal to the `String` of the same characters; dictionary keys are strings;
- arrays keep their order, size and nil elements (an empty array is **not** nil);
- graph-laid rows are regrouped by kind/type and sorted, so arrays of objects compare as multisets.

```smalltalk
| obj back |
obj  := someJsonShapedObject.
back := IsonGraphReader new read: (IsonGraphWriter new documentFor: obj).
IsonGraphCodec equivalent: obj to: back.   "=> true"
```

# Canonical, deterministic output

For a fixed logical value the writer produces **byte-identical** output regardless of construction
order: node-type blocks, rows within a block, edge-type blocks and columns are all sorted. This makes
an ISON document safe to content-address, diff, or use as a stable cached prefix. `IsonGraphCodec`
also offers `canonicalJsonOf:` (JSON with recursively sorted keys) and `sortedKeysCopyOf:` for the
same guarantee in JSON.

# The context packer

`IsonGraphContextPacker` fits the largest prefix of an already-prioritized collection into a token
budget and stamps the result with its estimated token count and a SHA-based digest, so a consumer can
pin the document and detect when it changes.

```smalltalk
| packer text |
packer := IsonGraphContextPacker new
    budgetTokens: 8000;
    yourself.
"aPackBlock answers the pack value (a dictionary) for its first N prioritized items;
 total is the full item count."
text := packer pack: aPackBlock total: itemCount.
```

The packer binary-searches for the largest N whose rendered document fits `budgetTokens` (estimated
conservatively, so the budget is not exceeded), then records `estimatedTokens`, whether it went
`overBudget`, and a content `digest`. Pass `strictGraphIds: true` or `edgeRowSchema:` to control how
it renders.

# The token estimator

`IsonGraphTokenEstimator estimate: aString` returns a cheap, vocabulary-free estimate: letter runs
cost `ceil(len / 9)`, digit runs `ceil(len / 3)`, every other non-blank character and every newline
cost 1, and spaces are free. It is calibrated to be **slightly conservative** (it never under-counts
on representative output), which is exactly what a budget check needs.

# Class reference

| Class                    | Role |
|--------------------------|------|
| `IsonGraphWriter`        | Serialize a JSON-shaped object to ISON (`documentFor:`), with `strictGraphIds:` and `edgeRowSchema:` options. |
| `IsonGraphReader`        | Parse ISON back to the equivalent object (`read:`), with a matching `edgeRowSchema:`. |
| `IsonGraphCodec`         | Scalar typing, quoting, normalization, equivalence (`equivalent:to:`), canonical JSON, id percent-encoding. Class-side utilities. |
| `IsonGraphEdgeRowSchema` | Configurable edge-row contract; `IsonGraphEdgeRowSchema default` is the neutral `source`/`target`/`edgeType` contract. |
| `IsonGraphContextPacker` | Budget-aware packing into one pinned, digest-stamped document. |
| `IsonGraphTokenEstimator`| Conservative, dependency-free token estimate (`estimate:`). |
| `IsonGraphReference`     | A `:kind:id` node reference. |
| `IsonGraphBlock`, `IsonGraphColumn`, `IsonGraphParsedBlock`, `IsonGraphPreRendered` | Internal building blocks of the writer/reader. |

# Specializing for your own data

If your reference rows use field names other than the neutral default, create a schema (or a subclass
of `IsonGraphEdgeRowSchema` with its own `default` on the class side) and hand it to the writer and
reader:

```smalltalk
| schema writer reader |
schema := IsonGraphEdgeRowSchema new
    sourceIdKey: 'src';   sourceKindKey: 'srcType';
    targetIdKey: 'dst';   targetKindKey: 'dstType';
    edgeTypeKey: 'rel';
    fromPrefix: 'src';    toPrefix: 'dst';
    yourself.

writer := IsonGraphWriter new edgeRowSchema: schema; yourself.
reader := IsonGraphReader new edgeRowSchema: schema; yourself.

| text |
text := writer documentFor: (Dictionary new
    at: 'results' put: { (Dictionary new
        at: 'src' put: '1'; at: 'srcType' put: 'n'; at: 'rel' put: 'links';
        at: 'dst' put: '2'; at: 'dstType' put: 'n'; yourself) };
    yourself).
"text contains an edges.links block with :n:1 / :n:2 references"
IsonGraphCodec equivalent: (reader read: text) to: (reader read: text).  "=> true"
```

The reader must be given the same schema the writer used; otherwise it cannot tell which columns name
the edge's endpoints and type.

# Contribute

**Working on your first Pull Request?** You can learn how from this *free* series
[How to Contribute to an Open Source Project on GitHub](https://egghead.io/series/how-to-contribute-to-an-open-source-project-on-github).

If you have discovered a bug or have a feature suggestion, feel free to create an issue on GitHub. If
you have any suggestions for how this package could be improved, please get in touch or suggest an
improvement using the GitHub issues page.

If you'd like to make some changes yourself:

- Fork this repository to your own GitHub account and then clone it to your local device.
- Make your changes.
- Add tests and run them.
- Add yourself as an author below.
- Submit a pull request with your changes.

This project follows the [all-contributors specification](https://github.com/kentcdodds/all-contributors).
Contributions of any kind are welcome.

## Version management

This project uses semantic versioning. Each stable release is assigned a version of the form
`vX.Y.Z`: **X** major, **Y** minor, **Z** patch. Bug-fix-only releases bump the patch; backward-
compatible features bump the minor; breaking changes bump the major.

# License

This software is licensed under the MIT License.

Copyright Hernán Morales Durand, 2026.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial
portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Authors

Hernán Morales Durand
