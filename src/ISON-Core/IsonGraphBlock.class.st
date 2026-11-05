Class {
	#name : 'IsonGraphBlock',
	#superclass : 'Object',
	#instVars : [
		'kind',
		'name',
		'columns',
		'rowCount'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'accessing' }
IsonGraphBlock >> columns [

	^ columns
]

{ #category : 'accessing' }
IsonGraphBlock >> columns: aCollection rowCount: anInteger [

	columns := aCollection asOrderedCollection.
	rowCount := anInteger
]

{ #category : 'accessing' }
IsonGraphBlock >> kind [

	^ kind
]

{ #category : 'accessing' }
IsonGraphBlock >> name [

	^ name
]

{ #category : 'rendering' }
IsonGraphBlock >> renderOn: aStream [
	"kind.name / field line / one line per row. Values in a single-column block are quoted when they
	 would otherwise read as a block header."

	| single |
	single := columns size = 1.
	aStream
		nextPutAll: kind;
		nextPut: $.;
		nextPutAll: name;
		nextPut: Character lf.
	columns
		do: [ :c | aStream nextPutAll: c fieldString ]
		separatedBy: [ aStream space ].
	aStream nextPut: Character lf.
	1 to: rowCount do: [ :i |
			columns
				do: [ :c |
						aStream nextPutAll:
							(IsonGraphCodec render: (c cells at: i) singleColumn: single) ]
				separatedBy: [ aStream space ].
			aStream nextPut: Character lf ]
]

{ #category : 'accessing' }
IsonGraphBlock >> rowCount [

	^ rowCount
]

{ #category : 'initialization' }
IsonGraphBlock >> setKind: aKind name: aName [

	kind := aKind.
	name := aName.
	columns := OrderedCollection new.
	rowCount := 0
]
