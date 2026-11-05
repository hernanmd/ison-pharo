"
Serializes a JSON-shaped value (Dictionary / Array / scalar) to ISON text: a set of newline-delimited, columnar blocks whose column headers are written once and shared by every row beneath them. Produces canonical, deterministic output (sorted blocks, rows and columns) so the same logical value always yields the same bytes.

Entry point: `documentFor:` answers the ISON String for an object.

Options:
- `strictGraphIds:` (default false) controls node-id percent-encoding. Readable mode escapes only whitespace, control characters and '%'; strict mode also escapes ':', '|', '""' and backslash so ids load into strict reference-graph readers.
- `edgeRowSchema:` supplies the IsonGraphEdgeRowSchema naming which row keys identify an edge's endpoints and type; defaults to the neutral source/target/edgeType contract.

A top-level value that is not a Dictionary is wrapped (the marker line carries ' wrapped') so arrays and scalars round-trip. The inverse is IsonGraphReader.
"
Class {
	#name : 'IsonGraphWriter',
	#superclass : 'Object',
	#instVars : [
		'blocks',
		'files',
		'fileIndex',
		'nodesKey',
		'refsKey',
		'wrapped',
		'strictGraphIds',
		'edgeRowSchema'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'encoding' }
IsonGraphWriter >> arrayColumnsNamed: aName values: values rowCount: aRowCount path: aPath allowGraph: aBoolean [
	"Arrays become a child block plus a count cell in the parent (nil = no array, 0 = empty array).
	 - arrays of scalars  -> list.<path>-<key>  (column v)
	 - arrays of objects  -> tab.<path>-<key>, or - once per document, top level only - the graph
	   layout nodes.<Kind> (rows with id+kind) / edges.<edgeType> (reference rows)
	 Child rows carry `r` (0-based parent row) unless the parent block has a single row. A child block
	 with no rows at all is not written (every count is 0 or ~)."

	| elems counts childPath childRows parents allScalar allObjects hint |
	elems := OrderedCollection new.
	values do: [ :v | v ifNotNil: [ elems addAll: v ] ].
	counts := (values collect: [ :v | v ifNotNil: [ v size ] ]) asArray.
	allScalar := elems allSatisfy: [ :e |
		             e isNil or: [ IsonGraphCodec isScalar: e ] ].
	allObjects := elems notEmpty and: [
		              elems allSatisfy: [ :e | e isDictionary ] ].
	(allScalar or: [ allObjects ]) ifFalse: [
		^ self jsonColumnNamed: aName values: values ].
	hint := allScalar
		        ifTrue: [ 'list' ]
		        ifFalse: [ 'tab' ].
	elems isEmpty ifTrue: [
		^ { (IsonGraphColumn new setName: aName hint: hint cells: counts) } ].
	(allObjects and: [ aBoolean and: [ aRowCount = 1 ] ]) ifTrue: [
			(nodesKey isNil and: [ self isNodeRowSet: elems ]) ifTrue: [
					nodesKey := aName.
					self encodeNodeRows: elems.
					^ { (IsonGraphColumn new
						   setName: aName
						   hint: 'nodes'
						   cells: counts) } ].
			(refsKey isNil and: [
				 nodesKey ~= #endpoints and: [ self isReferenceRowSet: elems ] ])
				ifTrue: [
						refsKey := aName.
						^ { (IsonGraphColumn new
							   setName: aName
							   hint: (self encodeReferenceRows: elems)
							   cells: counts) } ] ].
	childPath := aPath , '-' , aName.
	childRows := OrderedCollection new.
	parents := OrderedCollection new.
	values doWithIndex: [ :v :i |
			v ifNotNil: [
					v do: [ :e |
							childRows add: (allScalar
									 ifTrue: [
											 e ifNil: [ Dictionary new ] ifNotNil: [
													 Dictionary new
														 at: 'v' put: e;
														 yourself ] ]
									 ifFalse: [ e ]).
							parents add: i - 1 ] ] ].
	self
		encodeRows: childRows asArray
		kind: hint
		name: childPath
		path: childPath
		parents: (aRowCount > 1
				 ifTrue: [ parents ]
				 ifFalse: [ nil ])
		allowGraph: false.
	^ { (IsonGraphColumn new setName: aName hint: hint cells: counts) }
]

{ #category : 'encoding' }
IsonGraphWriter >> columnsForKey: aKey rows: rows path: aPath allowGraph: aBoolean [

	| values nonNil |
	values := (rows collect: [ :r | r at: aKey ifAbsent: [ nil ] ])
		          asArray.
	nonNil := values reject: [ :v | v isNil ].
	nonNil isEmpty ifTrue: [ ^ #(  ) ].
	(nonNil allSatisfy: [ :v | IsonGraphCodec isScalar: v ]) ifTrue: [
		^ self scalarColumnsNamed: aKey values: values ].
	(nonNil allSatisfy: [ :v | v isDictionary ]) ifTrue: [
			^ (self flattenedColumnsNamed: aKey values: values) ifNil: [
					  self
						  objectColumnsNamed: aKey
						  values: values
						  rowCount: rows size
						  path: aPath ] ].
	(nonNil allSatisfy: [ :v | v isArray ]) ifTrue: [
			^ self
				  arrayColumnsNamed: aKey
				  values: values
				  rowCount: rows size
				  path: aPath
				  allowGraph: aBoolean ].
	^ self jsonColumnNamed: aKey values: values
]

{ #category : 'writing' }
IsonGraphWriter >> documentFor: anObject [
	"Answer the ISON text for a JSON-shaped result (Dictionary / Array / scalar). Deterministic: the
	 same normalized input always yields the same bytes. Lossless under IsonGraphCodec class>>normalize:."

	| normalized root |
	normalized := IsonGraphCodec normalize: anObject.
	wrapped := normalized notNil and: [ normalized isDictionary not ].
	root := wrapped
		        ifTrue: [
				        Dictionary new
					        at: 'value' put: normalized;
					        yourself ]
		        ifFalse: [ normalized ifNil: [ Dictionary new ] ].
	blocks := OrderedCollection new.
	files := OrderedCollection new.
	fileIndex := Dictionary new.
	nodesKey := nil.
	refsKey := nil.
	self
		encodeRows: { root }
		kind: 'meta'
		name: 'result'
		path: 'result'
		parents: nil
		allowGraph: true.
	^ self render
]

{ #category : 'accessing' }
IsonGraphWriter >> edgeRowSchema [
	"The edge-row contract this writer recognizes (IsonGraphEdgeRowSchema). Defaults to the neutral
	 source/target/edgeType contract; a producer with different row keys sets its own."
	^ edgeRowSchema ifNil: [
		  edgeRowSchema := IsonGraphEdgeRowSchema default ]
]

{ #category : 'accessing' }
IsonGraphWriter >> edgeRowSchema: aSchema [

	edgeRowSchema := aSchema
]

{ #category : 'graph layout' }
IsonGraphWriter >> encodeNodeRows: rows [
	"nodes.<Kind> blocks, kinds and rows in ordinal order; `kind` is carried by the block name and ids
	 are graph-encoded so the reference ISONGraph reader accepts every one of them."

	| byKind |
	byKind := Dictionary new.
	rows do: [ :r |
			(byKind at: (r at: 'kind') ifAbsentPut: [ OrderedCollection new ])
				add: r ].
	byKind keys asSortedCollection do: [ :kind |
			| converted |
			converted := (byKind at: kind) asArray collect: [ :r |
					             | d |
					             d := r copy.
					             d removeKey: 'kind'.
					             d at: 'id' put: (IsonGraphCodec
							              encodeGraphId: (r at: 'id')
							              strict: self strictGraphIds).
					             d ].
			converted sort: [ :a :b | (a at: 'id') <= (b at: 'id') ].
			self
				encodeRows: converted
				kind: 'nodes'
				name: kind
				path: 'nodes-' , kind
				parents: nil
				allowGraph: false ]
]

{ #category : 'graph layout' }
IsonGraphWriter >> encodeReferenceRows: rows [
	"ISONGraph layout for reference rows, per the edgeRowSchema. Endpoint attributes (the schema's
	 from/to families, e.g. targetName, sourceCitation) move onto ONE nodes.<Kind> row per endpoint -
	 written once instead of once per edge - when they are consistent per node; edges.<edgeType> rows keep
	 source/target as :Kind:id and any other key. Answers the parent-column hint `refs[+family...]` the
	 reader needs to rebuild the rows. No producer-specific key names appear here; they come from schema."

	| schema structural families attrsByNode consistent nodeRows byType emitEndpoints |
	schema := self edgeRowSchema.
	emitEndpoints := nodesKey isNil.
	structural := schema structuralKeys.
	families := Set new.
	rows do: [ :r |
			r keysDo: [ :k |
				(schema familyRoleOf: k) ifNotNil: [ families add: k ] ] ].
	attrsByNode := Dictionary new.
	consistent := true.
	rows do: [ :r |
			#( 'from' 'to' ) do: [ :role |
					| nodeKey attrs |
					nodeKey := {
						           (r
							            at: (schema kindKeyForRole: role)
							            ifAbsent: [ nil ]).
						           (r at: (schema idKeyForRole: role) ifAbsent: [ nil ]) }.
					attrs := attrsByNode at: nodeKey ifAbsentPut: [ Dictionary new ].
					(families select: [ :f | (schema familyRoleOf: f) = role ]) do: [
							:f |
							| a v |
							a := schema attributeOf: f.
							v := r at: f ifAbsent: [ nil ].
							(attrs includesKey: a)
								ifTrue: [
										(IsonGraphCodec equivalentNormalized: (attrs at: a) to: v)
											ifFalse: [ consistent := false ] ]
								ifFalse: [ attrs at: a put: v ] ] ] ].
	(consistent and: [ emitEndpoints ]) ifFalse: [ families := Set new ].
	nodeRows := OrderedCollection new.
	attrsByNode keysAndValuesDo: [ :nodeKey :attrs |
			| d |
			d := Dictionary new.
			consistent ifTrue: [
				attrs keysAndValuesDo: [ :a :v | v ifNotNil: [ d at: a put: v ] ] ].
			d at: 'kind' put: nodeKey first.
			d at: 'id' put: nodeKey second.
			nodeRows add: d ].
	emitEndpoints ifTrue: [
			nodesKey := #endpoints.
			self encodeNodeRows: nodeRows ].
	byType := Dictionary new.
	rows do: [ :r |
			(byType
				 at: (r at: schema edgeTypeKey)
				 ifAbsentPut: [ OrderedCollection new ]) add: r ].
	byType keys asSortedCollection do: [ :type |
			| converted |
			converted := (byType at: type) asArray collect: [ :r |
					             | d |
					             d := Dictionary new.
					             d at: 'source' put: (IsonGraphReference new
							              setKind: (r at: (schema kindKeyForRole: 'from'))
							              id: (IsonGraphCodec
									               encodeGraphId:
									               (r at: (schema idKeyForRole: 'from'))
									               strict: self strictGraphIds)).
					             d at: 'target' put: (IsonGraphReference new
							              setKind: (r at: (schema kindKeyForRole: 'to'))
							              id: (IsonGraphCodec
									               encodeGraphId:
									               (r at: (schema idKeyForRole: 'to'))
									               strict: self strictGraphIds)).
					             r keysAndValuesDo: [ :k :v |
							             ((structural includes: k) or: [
								              families includes: k ]) ifFalse: [
								             d at: k put: v ] ].
					             d ].
			converted sort: [ :a :b |
					| sa sb |
					sa := (a at: 'source') isonString.
					sb := (b at: 'source') isonString.
					sa = sb
						ifTrue: [
						(a at: 'target') isonString <= (b at: 'target') isonString ]
						ifFalse: [ sa <= sb ] ].
			self
				encodeRows: converted
				kind: 'edges'
				name: type
				path: 'edges-' , type
				parents: nil
				allowGraph: false ].
	^ String streamContents: [ :s |
			  s nextPutAll: 'refs'.
			  families asSortedCollection do: [ :f |
					  s
						  nextPut: $+;
						  nextPutAll: f ] ]
]

{ #category : 'encoding' }
IsonGraphWriter >> encodeRows: rows kind: aKind name: aName path: aPath parents: parentIndexesOrNil allowGraph: aBoolean [
	"One block for a homogeneous-ish row set. Plain keys become columns (scalars as-is, objects flattened
	 to dotted columns, arrays to child blocks); non-plain keys travel in one `_x:json` bag per row."

	| block columns extras |
	block := IsonGraphBlock new setKind: aKind name: aName.
	blocks add: block.
	columns := OrderedCollection new.
	parentIndexesOrNil ifNotNil: [
			columns add: (IsonGraphColumn new
					 setName: 'r'
					 hint: nil
					 cells: parentIndexesOrNil asArray) ].
	((self orderedKeysOf: rows) select: [ :k |
		 IsonGraphCodec isPlainKey: k ]) do: [ :k |
			columns addAll: (self
					 columnsForKey: k
					 rows: rows
					 path: aPath
					 allowGraph: aBoolean) ].
	extras := rows collect: [ :r |
			          | bag |
			          bag := Dictionary new.
			          r keysAndValuesDo: [ :k :v |
				          (IsonGraphCodec isPlainKey: k) ifFalse: [
					          bag at: k put: v ] ].
			          bag isEmpty
				          ifTrue: [ nil ]
				          ifFalse: [ IsonGraphCodec canonicalJsonOf: bag ] ].
	(extras anySatisfy: [ :e | e notNil ]) ifTrue: [
			columns add:
				(IsonGraphColumn new
					 setName: '_x'
					 hint: 'json'
					 cells: extras asArray) ].
	columns isEmpty ifTrue: [
			columns add: (IsonGraphColumn new
					 setName: '_'
					 hint: nil
					 cells: (Array new: rows size)) ].
	block columns: columns rowCount: rows size.
	^ block
]

{ #category : 'encoding' }
IsonGraphWriter >> flattenedColumnsNamed: aName values: values [
	"Objects of scalars (nested any depth) become `name.sub[.sub]` columns. Answer nil when that is not
	 lossless; the caller falls back to a json column."

	| leafRows paths columns |
	leafRows := values collect: [ :v |
			            v ifNotNil: [
					            | leaves |
					            leaves := Dictionary new.
					            (self leavesOf: v prefix: aName into: leaves)
						            ifFalse: [ ^ nil ].
					            leaves ] ].
	paths := Set new.
	leafRows do: [ :d | d ifNotNil: [ paths addAll: d keys ] ].
	"A path that is a leaf somewhere and an object elsewhere cannot share one column set."
	(paths anySatisfy: [ :p |
		 paths anySatisfy: [ :q | q beginsWith: p , '.' ] ]) ifTrue: [
		^ nil ].
	columns := OrderedCollection new.
	paths asSortedCollection do: [ :p |
			columns addAll: (self
					 scalarColumnsNamed: p
					 values:
					 (leafRows collect: [ :d |
						  d ifNotNil: [ d at: p ifAbsent: [ nil ] ] ])) ].
	^ columns
]

{ #category : 'graph layout' }
IsonGraphWriter >> hasNoArrays: anObject [

	anObject isArray ifTrue: [ ^ false ].
	anObject isDictionary ifTrue: [
		^ anObject values allSatisfy: [ :v | self hasNoArrays: v ] ].
	^ true
]

{ #category : 'encoding' }
IsonGraphWriter >> intern: aPathString [
	"0-based index into the document's file table; first-seen order, so deterministic."

	^ fileIndex at: aPathString ifAbsentPut: [
			  files add: aPathString.
			  files size - 1 ]
]

{ #category : 'encoding' }
IsonGraphWriter >> isFileKey: aString [
	"Leaf keys whose (long, highly repeated) path values are interned into the `list.files` table."

	^ #( 'file' 'filePath' ) includes: aString
]

{ #category : 'graph layout' }
IsonGraphWriter >> isNodeRowSet: rows [
	"Rows the reference ISONGraph reader can load as nodes: id (string) + kind (identifier), unique
	 (kind,id), and no nested arrays (graph blocks carry no child blocks)."

	| seen |
	seen := Set new.
	^ rows allSatisfy: [ :r |
			  | id kind |
			  id := r at: 'id' ifAbsent: [ nil ].
			  kind := r at: 'kind' ifAbsent: [ nil ].
			  (id isString and: [ id notEmpty ]) and: [
					  (IsonGraphCodec isIdentifier: kind) and: [
							  (self hasNoArrays: r) and: [
									  (seen includes: {
											   kind.
											   id }) not and: [
											  seen add: {
													  kind.
													  id }.
											  true ] ] ] ] ]
]

{ #category : 'graph layout' }
IsonGraphWriter >> isReferenceId: anObject [
	"Any non-empty string: graph-block ids are percent-encoded (IsonGraphCodec class>>encodeGraphId:strict:)."

	^ anObject isString and: [ anObject notEmpty ]
]

{ #category : 'graph layout' }
IsonGraphWriter >> isReferenceRowSet: rows [
	"Rows writable as ISONGraph edges under the edgeRowSchema: id keys are unquoted-:Kind:id-writable,
	 kind + edgeType keys are identifiers, unique (type, source, target), no nested arrays."

	| schema seen |
	schema := self edgeRowSchema.
	seen := Set new.
	^ rows allSatisfy: [ :r |
			  | key |
			  ((self isReferenceId:
				    (r at: (schema idKeyForRole: 'from') ifAbsent: [ nil ])) and: [
					   (self isReferenceId:
						    (r at: (schema idKeyForRole: 'to') ifAbsent: [ nil ])) and: [
							   (IsonGraphCodec isIdentifier:
								    (r at: schema edgeTypeKey ifAbsent: [ nil ])) and: [
									   (IsonGraphCodec isIdentifier:
										    (r at: (schema kindKeyForRole: 'from') ifAbsent: [ nil ]))
										   and: [
												   (IsonGraphCodec isIdentifier:
													    (r
														     at: (schema kindKeyForRole: 'to')
														     ifAbsent: [ nil ])) and: [ self hasNoArrays: r ] ] ] ] ])
				  and: [
						  key := {
							         (r at: schema edgeTypeKey).
							         (r at: (schema kindKeyForRole: 'from')).
							         (r at: (schema idKeyForRole: 'from')).
							         (r at: (schema kindKeyForRole: 'to')).
							         (r at: (schema idKeyForRole: 'to')) }.
						  (seen includes: key) not and: [
								  seen add: key.
								  true ] ] ]
]

{ #category : 'encoding' }
IsonGraphWriter >> jsonColumnNamed: aName values: values [
	"Lossless fallback for shapes the tabular layout does not cover: one canonical JSON text per cell."

	^ { (IsonGraphColumn new
		   setName: aName
		   hint: 'json'
		   cells: (values collect: [ :v |
				    v ifNotNil: [ IsonGraphCodec canonicalJsonOf: v ] ]) asArray) }
]

{ #category : 'encoding' }
IsonGraphWriter >> leavesOf: aDictionary prefix: aPrefix into: aResult [
	"Flatten a nested object into dotted-path -> scalar. Answer false when the object cannot be flattened
	 losslessly (non-plain key, array value, unrenderable float)."

	aDictionary keysAndValuesDo: [ :k :v |
			| p |
			(IsonGraphCodec isPlainKey: k) ifFalse: [ ^ false ].
			p := aPrefix , '.' , k.
			v isDictionary
				ifTrue: [
				(self leavesOf: v prefix: p into: aResult) ifFalse: [ ^ false ] ]
				ifFalse: [
						((IsonGraphCodec isScalar: v) and: [
							 IsonGraphCodec isRenderableFloat: v ]) ifFalse: [ ^ false ].
						aResult at: p put: v ] ].
	^ true
]

{ #category : 'encoding' }
IsonGraphWriter >> objectColumnsNamed: aName values: values rowCount: aRowCount path: aPath [
	"Objects that cannot be flattened (they nest arrays) become a one-row-per-parent child block
	 tab.<path>-<key>; the parent cell is 1 (present) or ~ (absent)."

	| childPath childRows parents |
	childPath := aPath , '-' , aName.
	childRows := OrderedCollection new.
	parents := OrderedCollection new.
	values doWithIndex: [ :v :i |
			v ifNotNil: [
					childRows add: v.
					parents add: i - 1 ] ].
	self
		encodeRows: childRows asArray
		kind: 'tab'
		name: childPath
		path: childPath
		parents: (aRowCount > 1
				 ifTrue: [ parents ]
				 ifFalse: [ nil ])
		allowGraph: false.
	^ { (IsonGraphColumn new
		   setName: aName
		   hint: 'obj'
		   cells: (values collect: [ :v | v ifNotNil: [ 1 ] ]) asArray) }
]

{ #category : 'private' }
IsonGraphWriter >> orderedKeysOf: rows [
	"Union of keys over the rows; identity-ish keys first, then ordinal order."

	| keys priority ordered |
	keys := Set new.
	rows do: [ :r | keys addAll: r keys ].
	priority := #( 'id' 'source' 'target' 'name' 'kind' ).
	ordered := OrderedCollection new.
	priority do: [ :p | (keys includes: p) ifTrue: [ ordered add: p ] ].
	(keys reject: [ :k | priority includes: k ]) asSortedCollection do: [
		:k | ordered add: k ].
	^ ordered
]

{ #category : 'writing' }
IsonGraphWriter >> render [
	"Format marker comment, meta.result, the interned file table, then every other block in creation
	 order (parents before children). Blocks are separated by one blank line."

	| ordered |
	ordered := OrderedCollection new.
	ordered add: blocks first.
	files isEmpty ifFalse: [
			ordered add: ((IsonGraphBlock new setKind: 'list' name: 'files')
					 columns:
						 { (IsonGraphColumn new
							  setName: 'v'
							  hint: nil
							  cells: files asArray) }
					 rowCount: files size;
					 yourself) ].
	ordered addAll: blocks allButFirst.
	^ String streamContents: [ :s |
			  s nextPutAll: '# ison1'.
			  wrapped ifTrue: [ s nextPutAll: ' wrapped' ].
			  s nextPut: Character lf.
			  ordered
				  do: [ :b | b renderOn: s ]
				  separatedBy: [ s nextPut: Character lf ] ]
]

{ #category : 'encoding' }
IsonGraphWriter >> scalarColumnsNamed: aName values: values [

	| leaf |
	(values allSatisfy: [ :v | IsonGraphCodec isRenderableFloat: v ])
		ifFalse: [ ^ self jsonColumnNamed: aName values: values ].
	leaf := (aName includes: $.)
		        ifTrue: [ aName copyAfterLast: $. ]
		        ifFalse: [ aName ].
	((self isFileKey: leaf) and: [
		 values allSatisfy: [ :v | v isNil or: [ v isString ] ] ]) ifTrue: [
			^ { (IsonGraphColumn new
				   setName: aName
				   hint: 'file'
				   cells:
				   (values collect: [ :v | v ifNotNil: [ self intern: v ] ])) } ].
	^ { (IsonGraphColumn new
		   setName: aName
		   hint: nil
		   cells: values asArray) }
]

{ #category : 'accessing' }
IsonGraphWriter >> strictGraphIds [
	"false (default): readable ids for LLM context. true: ids the reference ISONGraph reader accepts."

	^ strictGraphIds ifNil: [ false ]
]

{ #category : 'accessing' }
IsonGraphWriter >> strictGraphIds: aBoolean [

	strictGraphIds := aBoolean
]
