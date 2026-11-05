Class {
	#name : 'IsonGraphCodec',
	#superclass : 'Object',
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'comparing' }
IsonGraphCodec class >> canonicalJsonOf: anObject [
	"JSON text with recursively sorted object keys - a deterministic identity for a normalized value."

	^ self jsonString: (self sortedKeysCopyOf: anObject)
]

{ #category : 'graph ids' }
IsonGraphCodec class >> decodeGraphId: aString [

	| in |
	(aString includes: $%) ifFalse: [ ^ aString ].
	in := ReadStream on: aString.
	^ String streamContents: [ :s |
			  [ in atEnd ] whileFalse: [
					  | c |
					  c := in next.
					  c = $%
						  ifTrue: [
								  | hex |
								  hex := in next: 2.
								  s nextPut:
									  (Character value: (Integer readFrom: hex base: 16)) ]
						  ifFalse: [ s nextPut: c ] ] ]
]

{ #category : 'graph ids' }
IsonGraphCodec class >> encodeGraphId: aString strict: aBoolean [
	"Graph-block ids (nodes.<Kind> id column and :Kind:id references) are percent-encoded only where the
	 layout needs it. Readable mode (default, for LLM context): whitespace/control and '%' only, so ids stay
	 verbatim (`egl://a/b`). Strict mode (reference ISONGraph loadability): also ':' '|' quote backslash,
	 because ISONGraph rejects those in node ids (`egl%3A//a/b`). The reader decodes both."

	| escaped |
	escaped := aBoolean
		           ifTrue: [ [ :c | self isGraphIdEscaped: c ] ]
		           ifFalse: [
		           [ :c |
		           c asInteger < 33 or: [ c asInteger = 127 or: [ c = $% ] ] ] ].
	(aString anySatisfy: escaped) ifFalse: [ ^ aString ].
	^ String streamContents: [ :s |
			  aString do: [ :c |
					  (escaped value: c)
						  ifTrue: [
								  s
									  nextPut: $%;
									  nextPutAll:
										  ((c asInteger printStringBase: 16) asUppercase
											   padLeftTo: 2
											   with: $0) ]
						  ifFalse: [ s nextPut: c ] ] ]
]

{ #category : 'comparing' }
IsonGraphCodec class >> equivalent: a to: b [
	"Equality under the IR-ISON equivalence (see normalize:), with ONE relaxation: an array whose elements
	 are all objects compares as a multiset, because graph-laid rows (nodes.<Kind> / edges.<type>) are
	 regrouped by kind/type and sorted on the wire. Arrays of scalars compare positionally."

	| na nb |
	na := self normalize: a.
	nb := self normalize: b.
	^ self equivalentNormalized: na to: nb
]

{ #category : 'comparing' }
IsonGraphCodec class >> equivalentNormalized: a to: b [

	| ka kb sa sb |
	(a isNil or: [ b isNil ]) ifTrue: [ ^ a isNil and: [ b isNil ] ].
	(a isDictionary or: [ b isDictionary ]) ifTrue: [
			(a isDictionary and: [ b isDictionary ]) ifFalse: [ ^ false ].
			ka := a keys asSortedCollection asArray.
			kb := b keys asSortedCollection asArray.
			ka = kb ifFalse: [ ^ false ].
			^ ka allSatisfy: [ :k |
				  self equivalentNormalized: (a at: k) to: (b at: k) ] ].
	(a isArray or: [ b isArray ]) ifTrue: [
			(a isArray and: [ b isArray ]) ifFalse: [ ^ false ].
			a size = b size ifFalse: [ ^ false ].
			((a allSatisfy: [ :e | e isDictionary ]) and: [
				 b allSatisfy: [ :e | e isDictionary ] ]) ifTrue: [
					sa := (a collect: [ :e | self canonicalJsonOf: e ])
						      asSortedCollection asArray.
					sb := (b collect: [ :e | self canonicalJsonOf: e ])
						      asSortedCollection asArray.
					^ sa = sb ].
			^ (1 to: a size) allSatisfy: [ :i |
				  self equivalentNormalized: (a at: i) to: (b at: i) ] ].
	(a isNumber and: [ b isNumber ]) ifTrue: [ ^ a = b ].
	^ a = b
]

{ #category : 'graph ids' }
IsonGraphCodec class >> isGraphIdEscaped: aCharacter [

	| v |
	v := aCharacter asInteger.
	^ v < 33 or: [
		  v = 127 or: [
			  v = 92 or: [ #( $: $| $% $" ) includes: aCharacter ] ] ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isIdentifier: aString [
	"ISON block-name part: [a-zA-Z_][a-zA-Z0-9_-]*"

	aString isString ifFalse: [ ^ false ].
	aString isEmpty ifTrue: [ ^ false ].
	((self isNameCharacter: aString first) and: [
		 aString first isDigit not and: [ aString first ~= $- ] ]) ifFalse: [
		^ false ].
	^ aString allSatisfy: [ :c | self isNameCharacter: c ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isIsonFloat: aString [
	"-?[0-9]+\.[0-9]+"

	| dot |
	dot := aString indexOf: $..
	dot = 0 ifTrue: [ ^ false ].
	^ (self isIsonInteger: (aString copyFrom: 1 to: dot - 1)) and: [
			  | frac |
			  frac := aString copyFrom: dot + 1 to: aString size.
			  frac notEmpty and: [ frac allSatisfy: [ :c | c isDigit ] ] ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isIsonInteger: aString [
	"-?[0-9]+"

	| body |
	aString isEmpty ifTrue: [ ^ false ].
	body := aString first = $-
		        ifTrue: [ aString allButFirst ]
		        ifFalse: [ aString ].
	^ body notEmpty and: [ body allSatisfy: [ :c | c isDigit ] ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isNameCharacter: aCharacter [
	"ASCII [A-Za-z0-9_-] (the ISON identifier alphabet; non-ASCII letters are excluded on purpose)."

	^ aCharacter asInteger < 128 and: [
			  aCharacter isAlphaNumeric or: [
				  aCharacter = $_ or: [ aCharacter = $- ] ] ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isPlainKey: aString [
	"A key that can be written as an IR-ISON column name or as part of a child-block name / dotted
	 flattened path. Reserved names (`r` parent index, `_` placeholder, `_x` extra-key bag) are not plain."

	aString isString ifFalse: [ ^ false ].
	aString isEmpty ifTrue: [ ^ false ].
	(#( 'r' '_' '_x' ) includes: aString) ifTrue: [ ^ false ].
	^ aString allSatisfy: [ :c | self isNameCharacter: c ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isRenderableFloat: aFloat [
	"A Float whose printString reads back as the same ISON float (-?[0-9]+.[0-9]+)."

	| s |
	aFloat isFloat ifFalse: [ ^ true ].
	(aFloat isNaN or: [ aFloat isInfinite ]) ifTrue: [ ^ false ].
	s := aFloat printString.
	^ (self isIsonFloat: s) and: [ (Number readFrom: s) = aFloat ]
]

{ #category : 'testing' }
IsonGraphCodec class >> isScalar: anObject [

	^ anObject isString or: [
			  anObject isNumber or: [
					  anObject == true or: [
						  anObject == false or: [ anObject class == IsonGraphReference ] ] ] ]
]

{ #category : 'rendering' }
IsonGraphCodec class >> jsonString: anObject [

	^ String streamContents: [ :s |
		  (NeoJSONWriter on: s) nextPut: anObject ]
]

{ #category : 'testing' }
IsonGraphCodec class >> looksLikeBlockHeader: aString [
	"kind.name with both parts identifiers - such a token alone on a line would start a new block."

	| parts |
	parts := aString substrings: '.'.
	(aString occurrencesOf: $.) = 1 ifFalse: [ ^ false ].
	parts size = 2 ifFalse: [ ^ false ].
	^ (self isIdentifier: parts first) and: [
		  self isIdentifier: parts last ]
]

{ #category : 'testing' }
IsonGraphCodec class >> looksLikeNumber: aString [
	"Anything Python's float() could accept in a plain decimal/exponent shape: [+-]?digits/dots[e[+-]digits].
	 Deliberately broad (e.g. '1.2.3' counts) - quoting a non-number costs two characters, misreading one
	 changes its type."

	| s i sawDigit |
	s := aString.
	i := 1.
	(s notEmpty and: [ s first = $+ or: [ s first = $- ] ]) ifTrue: [
		i := 2 ].
	sawDigit := false.
	[
		i <= s size and: [
			(s at: i) isDigit or: [ (s at: i) = $. or: [ (s at: i) = $_ ] ] ] ]
		whileTrue: [
				(s at: i) isDigit ifTrue: [ sawDigit := true ].
				i := i + 1 ].
	sawDigit ifFalse: [ ^ false ].
	i > s size ifTrue: [ ^ true ].
	((s at: i) = $e or: [ (s at: i) = $E ]) ifFalse: [ ^ false ].
	i := i + 1.
	(i <= s size and: [ (s at: i) = $+ or: [ (s at: i) = $- ] ]) ifTrue: [
		i := i + 1 ].
	i > s size ifTrue: [ ^ false ].
	^ (s copyFrom: i to: s size) allSatisfy: [ :c | c isDigit ]
]

{ #category : 'rendering' }
IsonGraphCodec class >> needsQuote: aString singleColumn: aBoolean [
	"Superset of ison-py's ISON _quote_if_needed, so the reference parser reads every value back with
	 the same type. Quoting is never wrong, only slightly more expensive, so ambiguity resolves to quote."

	| lower |
	aString isEmpty ifTrue: [ ^ true ].
	(aString anySatisfy: [ :c |
		 c asInteger < 33 or: [ c = $" or: [ c asInteger = 92 ] ] ])
		ifTrue: [ ^ true ].
	(aString first = $# or: [ aString first = $: ]) ifTrue: [ ^ true ].
	(aString beginsWith: '---') ifTrue: [ ^ true ].
	(#( 'true' 'false' 'null' '~' ) includes: aString) ifTrue: [ ^ true ].
	(self looksLikeNumber: aString) ifTrue: [ ^ true ].
	lower := aString asLowercase.
	(#( 'inf' '-inf' '+inf' 'nan' '-nan' '+nan' 'infinity' '-infinity'
	    '+infinity' ) includes: lower) ifTrue: [ ^ true ].
	(aBoolean and: [ self looksLikeBlockHeader: aString ]) ifTrue: [
		^ true ].
	^ false
]

{ #category : 'normalizing' }
IsonGraphCodec class >> normalize: anObject [
	"The IR-ISON equivalence used by writer, reader and tests. JSON-semantics simplification, stated once:
	 - a nil-valued key is the same as an absent key;
	 - an object that has no non-nil entries is the same as nil (so `properties: {}` == absent);
	 - Symbols are Strings, Fractions/ScaledDecimals are Floats, dictionary keys are Strings.
	 Arrays keep their order, their size and their nil elements (an empty array is NOT nil)."

	| result |
	anObject ifNil: [ ^ nil ].
	anObject isSymbol ifTrue: [ ^ anObject asString ].
	anObject isString ifTrue: [ ^ anObject ].
	(anObject == true or: [ anObject == false ]) ifTrue: [ ^ anObject ].
	anObject isInteger ifTrue: [ ^ anObject ].
	anObject isFloat ifTrue: [ ^ anObject ].
	anObject isNumber ifTrue: [ ^ anObject asFloat ].
	anObject isCharacter ifTrue: [ ^ anObject asString ].
	anObject isDictionary ifTrue: [
			result := Dictionary new.
			anObject keysAndValuesDo: [ :k :v |
				(self normalize: v) ifNotNil: [ :nv |
					result at: k asString put: nv ] ].
			^ result isEmpty
				  ifTrue: [ nil ]
				  ifFalse: [ result ] ].
	(anObject isCollection and: [ anObject isString not ]) ifTrue: [
		^ anObject asArray collect: [ :each | self normalize: each ] ].
	^ anObject printString
]

{ #category : 'rendering' }
IsonGraphCodec class >> quote: aString [
	"ISON quoted string. Escapes are built from characters (not literals) on purpose."

	| bs |
	bs := Character value: 92.
	^ String streamContents: [ :s |
			  s nextPut: $".
			  aString do: [ :c |
					  c = bs
						  ifTrue: [
								  s
									  nextPut: bs;
									  nextPut: bs ]
						  ifFalse: [
								  c = $"
									  ifTrue: [
											  s
												  nextPut: bs;
												  nextPut: $" ]
									  ifFalse: [
											  c = Character lf
												  ifTrue: [
														  s
															  nextPut: bs;
															  nextPut: $n ]
												  ifFalse: [
														  c = Character tab
															  ifTrue: [
																	  s
																		  nextPut: bs;
																		  nextPut: $t ]
															  ifFalse: [
																	  c = Character cr
																		  ifTrue: [
																				  s
																					  nextPut: bs;
																					  nextPut: $r ]
																		  ifFalse: [ s nextPut: c ] ] ] ] ] ].
			  s nextPut: $" ]
]

{ #category : 'rendering' }
IsonGraphCodec class >> render: aValue singleColumn: aBoolean [
	"One ISON cell. Values reaching here are already normalized scalars (or nil / a reference)."

	aValue ifNil: [ ^ '~' ].
	aValue == true ifTrue: [ ^ 'true' ].
	aValue == false ifTrue: [ ^ 'false' ].
	aValue class == IsonGraphReference ifTrue: [ ^ aValue isonString ].
	aValue isInteger ifTrue: [ ^ aValue printString ].
	aValue isFloat ifTrue: [ ^ aValue printString ].
	^ (self needsQuote: aValue singleColumn: aBoolean)
		  ifTrue: [ self quote: aValue ]
		  ifFalse: [ aValue ]
]

{ #category : 'comparing' }
IsonGraphCodec class >> sortedKeysCopyOf: anObject [
	"A copy in which every Dictionary is an OrderedDictionary with keys in ordinal order (so NeoJSON
	 emits them sorted). Used for canonical JSON (comparison, and the deterministic JSONL export mode)."

	| od |
	anObject isDictionary ifTrue: [
			od := OrderedDictionary new.
			(anObject keys asSortedCollection: [ :x :y |
				 x asString <= y asString ]) do: [ :k |
				od at: k put: (self sortedKeysCopyOf: (anObject at: k)) ].
			^ od ].
	(anObject isCollection and: [ anObject isString not ]) ifTrue: [
		^ anObject asArray collect: [ :e | self sortedKeysCopyOf: e ] ].
	^ anObject
]
