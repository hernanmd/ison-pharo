Class {
	#name : 'IsonGraphReader',
	#superclass : 'Object',
	#instVars : [
		'blocks',
		'blockIndex',
		'files',
		'wrapped',
		'decodedCache'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'reading' }
IsonGraphReader >> childRowsOf: aBlockName parent: aRowIndex count: aCount [
	"The rows of a child block that belong to parent row aRowIndex (all rows when the child carries no
	 `r` column). The parent's count cell is checked, so a truncated document fails loudly."

	| grouped rows |
	aCount = 0 ifTrue: [ ^ #(  ) ].
	grouped := decodedCache at: aBlockName ifAbsentPut: [
			           | block g |
			           block := blockIndex
				                    at: aBlockName
				                    ifAbsent: [
				                    self error:
					                    'IR-ISON: missing block ' , aBlockName ].
			           g := Dictionary new.
			           (self
				            decodeBlock: block
				            path: (aBlockName copyAfter: $.)) do: [ :assoc |
					           (g
						            at: (assoc key ifNil: [ #all ])
						            ifAbsentPut: [ OrderedCollection new ]) add:
						           assoc value ].
			           g ].
	rows := grouped
		        at: aRowIndex
		        ifAbsent: [ grouped at: #all ifAbsent: [ #(  ) ] ].
	rows size = aCount ifFalse: [
			self error:
				'IR-ISON: ' , aBlockName , ' has ' , rows size printString
				, ' rows for parent ' , aRowIndex printString , ', expected '
				, aCount printString ].
	^ rows
]

{ #category : 'reading' }
IsonGraphReader >> decodeBlock: aBlock path: aPath [
	"Answer an OrderedCollection of (parentIndexOrNil -> rowDictionary), in row order."

	| result |
	result := OrderedCollection new.
	aBlock rows doWithIndex: [ :values :i |
			| row parent |
			row := Dictionary new.
			parent := nil.
			aBlock fields doWithIndex: [ :fname :j |
					| hint v |
					hint := aBlock hints at: j.
					v := j <= values size
						     ifTrue: [ values at: j ]
						     ifFalse: [ nil ].
					(fname = 'r' and: [ hint isNil ])
						ifTrue: [ parent := v ]
						ifFalse: [
								(fname = '_' and: [ hint isNil ]) ifFalse: [
										(fname = '_x' and: [ hint = 'json' ])
											ifTrue: [
													v ifNotNil: [
															(NeoJSONReader fromString: v) keysAndValuesDo: [ :k :x |
																row at: k put: x ] ] ]
											ifFalse: [
													(self
														 decodeCell: v
														 hint: hint
														 name: fname
														 path: aPath
														 rowIndex: i - 1) ifNotNil: [ :d |
														self put: d at: fname into: row ] ] ] ] ].
			result add: parent -> row ].
	^ result
]

{ #category : 'reading' }
IsonGraphReader >> decodeCell: aValue hint: aHint name: aName path: aPath rowIndex: aRowIndex [

	| childName |
	aHint ifNil: [ ^ aValue ].
	aValue ifNil: [ ^ nil ].
	aHint = 'json' ifTrue: [ ^ NeoJSONReader fromString: aValue ].
	aHint = 'file' ifTrue: [ ^ files at: aValue + 1 ].
	aHint = 'list' ifTrue: [
			^ ((self
				    childRowsOf: 'list.' , aPath , '-' , aName
				    parent: aRowIndex
				    count: aValue) collect: [ :d | d at: 'v' ifAbsent: [ nil ] ])
				  asArray ].
	aHint = 'tab' ifTrue: [
			^ (self
				   childRowsOf: 'tab.' , aPath , '-' , aName
				   parent: aRowIndex
				   count: aValue) asArray ].
	aHint = 'obj' ifTrue: [
			childName := 'tab.' , aPath , '-' , aName.
			^ (self childRowsOf: childName parent: aRowIndex count: 1) first ].
	aHint = 'nodes' ifTrue: [ ^ self graphNodeRowsCount: aValue ].
	(aHint = 'refs' or: [ aHint beginsWith: 'refs+' ]) ifTrue: [
			^ self
				  graphReferenceRowsCount: aValue
				  families: (aHint substrings: '+') allButFirst ].
	"Unknown hint: forward-compatible, keep the raw cell."
	^ aValue
]

{ #category : 'reading' }
IsonGraphReader >> graphNodeRows [
	"Every nodes.<Kind> row as a dictionary with `kind` restored and its id graph-decoded."

	| rows |
	rows := OrderedCollection new.
	blocks do: [ :b |
			b kind = 'nodes' ifTrue: [
					(self decodeBlock: b path: 'nodes-' , b name) do: [ :assoc |
							| d |
							d := assoc value.
							d at: 'kind' put: b name.
							(d at: 'id' ifAbsent: [ nil ]) ifNotNil: [ :id |
								d at: 'id' put: (IsonGraphCodec decodeGraphId: id asString) ].
							rows add: d ] ] ].
	^ rows
]

{ #category : 'reading' }
IsonGraphReader >> graphNodeRowsCount: aCount [

	| rows |
	rows := self graphNodeRows.
	rows size = aCount ifFalse: [
			self error:
				'IR-ISON: node rows ' , rows size printString , ' expected '
				, aCount printString ].
	^ rows asArray
]

{ #category : 'reading' }
IsonGraphReader >> graphReferenceRowsCount: aCount families: aFamilyArray [
	"Rebuild reference rows from edges.<edgeType> blocks; endpoint attributes named by the families
	 (e.g. toName, fromCitation) come back from the endpoint's nodes.<Kind> row."

	| endpoints rows |
	endpoints := Dictionary new.
	self graphNodeRows do: [ :d |
			endpoints
				at: {
						(d at: 'kind').
						(d at: 'id') }
				put: d ].
	rows := OrderedCollection new.
	blocks do: [ :b |
			b kind = 'edges' ifTrue: [
					(self decodeBlock: b path: 'edges-' , b name) do: [ :assoc |
							| d source target |
							d := assoc value.
							source := d removeKey: 'source' ifAbsent: [ nil ].
							target := d removeKey: 'target' ifAbsent: [ nil ].
							d at: 'edgeType' put: b name.
							source ifNotNil: [
									d at: 'fromId' put: (IsonGraphCodec decodeGraphId: source id).
									source kind ifNotNil: [ :k | d at: 'fromKind' put: k ] ].
							target ifNotNil: [
									d at: 'toId' put: (IsonGraphCodec decodeGraphId: target id).
									target kind ifNotNil: [ :k | d at: 'toKind' put: k ] ].
							aFamilyArray do: [ :family |
									| role node attr |
									role := (family beginsWith: 'from')
										        ifTrue: [ 'from' ]
										        ifFalse: [ 'to' ].
									node := endpoints
										        at: {
												        (d at: role , 'Kind' ifAbsent: [ nil ]).
												        (d at: role , 'Id' ifAbsent: [ nil ]) }
										        ifAbsent: [ nil ].
									attr := family allButFirst: role size.
									attr := attr first asLowercase asString , attr allButFirst.
									(node ifNotNil: [ node at: attr ifAbsent: [ nil ] ])
										ifNotNil: [ :v | d at: family put: v ] ].
							rows add: d ] ] ].
	rows size = aCount ifFalse: [
			self error:
				'IR-ISON: reference rows ' , rows size printString , ' expected '
				, aCount printString ].
	^ rows asArray
]

{ #category : 'parsing' }
IsonGraphReader >> infer: aToken quoted: aBoolean [
	"ISON type inference, same order as ison-py: quoted -> string; true/false; null/~; int; float;
	 :ref / :Kind:id; otherwise string."

	| rest |
	aBoolean ifTrue: [ ^ aToken ].
	aToken = 'true' ifTrue: [ ^ true ].
	aToken = 'false' ifTrue: [ ^ false ].
	(aToken = 'null' or: [ aToken = '~' ]) ifTrue: [ ^ nil ].
	(IsonGraphCodec isIsonInteger: aToken) ifTrue: [
		^ Integer readFrom: aToken ].
	(IsonGraphCodec isIsonFloat: aToken) ifTrue: [
		^ Number readFrom: aToken ].
	(aToken size > 1 and: [ aToken first = $: ]) ifTrue: [
			rest := aToken allButFirst.
			^ (rest includes: $:)
				  ifTrue: [
						  IsonGraphReference new
							  setKind: (rest copyUpTo: $:)
							  id: (rest copyAfter: $:) ]
				  ifFalse: [ IsonGraphReference new setKind: nil id: rest ] ].
	^ aToken
]

{ #category : 'parsing' }
IsonGraphReader >> parse: aString [
	"Split the document into blocks (kind.name / field line / rows until a blank line). Comments (#)
	 are skipped; the `# ir-ison 1 [wrapped]` marker is honoured."

	| lines i |
	lines := aString lines.
	i := 1.
	[ i <= lines size ] whileTrue: [
			| line |
			line := (lines at: i) trimBoth.
			(line isEmpty or: [ line first = $# ])
				ifTrue: [
						(line beginsWith: '# ir-ison') ifTrue: [
							wrapped := wrapped or: [ line substrings includes: 'wrapped' ] ].
						i := i + 1 ]
				ifFalse: [
						| kind name fieldTokens fields hints block |
						(line includes: $.) ifFalse: [
							self error: 'IR-ISON: invalid block header ' , line ].
						kind := line copyUpTo: $..
						name := line copyAfter: $..
						i := i + 1.
						[
							i <= lines size and: [
									(lines at: i) trimBoth isEmpty or: [
										(lines at: i) trimBoth first = $# ] ] ] whileTrue: [
							i := i + 1 ].
						i > lines size ifTrue: [
							self error: 'IR-ISON: block ' , line , ' has no field line' ].
						fieldTokens := (self rawTokensOf: (lines at: i)) collect: [ :a |
							               a key ].
						fields := fieldTokens collect: [ :t |
								          (t includes: $:)
									          ifTrue: [ t copyUpTo: $: ]
									          ifFalse: [ t ] ].
						hints := fieldTokens collect: [ :t |
								         (t includes: $:)
									         ifTrue: [ t copyAfter: $: ]
									         ifFalse: [ nil ] ].
						block := IsonGraphParsedBlock new
							         setKind: kind
							         name: name
							         fields: fields asArray
							         hints: hints asArray.
						i := i + 1.
						[ i <= lines size and: [ (lines at: i) trimBoth notEmpty ] ]
							whileTrue: [
									| raw stripped |
									raw := lines at: i.
									stripped := raw trimBoth.
									(stripped first = $# or: [ stripped beginsWith: '---' ])
										ifTrue: [ i := i + 1 ]
										ifFalse: [
												(stripped substrings size = 1 and: [
													 IsonGraphCodec looksLikeBlockHeader: stripped ])
													ifTrue: [
													i := lines size + 1 "unreachable for writer output; stop the block" ]
													ifFalse: [
															block rows add:
																((self rawTokensOf: raw) collect: [ :a |
																	 self infer: a key quoted: a value ]) asArray.
															i := i + 1 ] ] ].
						blocks add: block.
						blockIndex at: block fullName put: block ] ]
]

{ #category : 'reading' }
IsonGraphReader >> put: aValue at: aDottedName into: aDictionary [
	"Flattened columns (`a.b.c`) rebuild nested objects; objects are only created for non-nil leaves."

	| parts target |
	parts := aDottedName substrings: '.'.
	target := aDictionary.
	parts allButLast do: [ :p |
		target := target at: p ifAbsentPut: [ Dictionary new ] ].
	target at: parts last put: aValue
]

{ #category : 'parsing' }
IsonGraphReader >> rawTokensOf: aLine [
	"ISON tokenizer: whitespace-separated tokens, double-quoted strings with backslash escapes
	 (n t r and any other escaped character literally). Answers Associations token -> wasQuoted."

	| tokens pos size bs |
	bs := Character value: 92.
	tokens := OrderedCollection new.
	pos := 1.
	size := aLine size.
	[
		[
			pos <= size and: [
					(aLine at: pos) = Character space or: [
						(aLine at: pos) = Character tab ] ] ] whileTrue: [
			pos := pos + 1 ].
		pos <= size ] whileTrue: [
			(aLine at: pos) = $"
				ifTrue: [
						| out closed |
						out := WriteStream on: String new.
						closed := false.
						pos := pos + 1.
						[ closed or: [ pos > size ] ] whileFalse: [
								| c |
								c := aLine at: pos.
								c = $"
									ifTrue: [ closed := true ]
									ifFalse: [
											c = bs
												ifTrue: [
														pos := pos + 1.
														pos > size ifTrue: [
															self error: 'IR-ISON: dangling escape' ].
														c := aLine at: pos.
														out nextPut: (c = $n
																 ifTrue: [ Character lf ]
																 ifFalse: [
																		 c = $t
																			 ifTrue: [ Character tab ]
																			 ifFalse: [
																					 c = $r
																						 ifTrue: [ Character cr ]
																						 ifFalse: [ c ] ] ]) ]
												ifFalse: [ out nextPut: c ] ].
								pos := pos + 1 ].
						closed ifFalse: [
							self error: 'IR-ISON: unterminated quoted string' ].
						tokens add: out contents -> true ]
				ifFalse: [
						| start |
						start := pos.
						[
							pos <= size and: [
									((aLine at: pos) = Character space or: [
										 (aLine at: pos) = Character tab ]) not ] ] whileTrue: [
							pos := pos + 1 ].
						tokens add: (aLine copyFrom: start to: pos - 1) -> false ] ].
	^ tokens
]

{ #category : 'reading' }
IsonGraphReader >> read: aString [
	"Answer the normalized JSON-shaped object an IR-ISON document encodes (inverse of
	 SmtIRIsonWriter>>documentFor:, up to SmtIRIsonCodec equivalence)."

	| meta root |
	blocks := OrderedCollection new.
	blockIndex := Dictionary new.
	decodedCache := Dictionary new.
	wrapped := false.
	self parse: aString.
	files := (blockIndex at: 'list.files' ifAbsent: [ nil ])
		         ifNil: [ #(  ) ]
		         ifNotNil: [ :b |
		         (b rows collect: [ :r | r first ]) asArray ].
	meta := blockIndex
		        at: 'meta.result'
		        ifAbsent: [
		        self error: 'IR-ISON: missing meta.result block' ].
	root := (self decodeBlock: meta path: 'result') first value.
	^ wrapped
		  ifTrue: [ root at: 'value' ifAbsent: [ nil ] ]
		  ifFalse: [
				  root isEmpty
					  ifTrue: [ nil ]
					  ifFalse: [ root ] ]
]
