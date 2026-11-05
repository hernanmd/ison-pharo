"
Represents one block being READ: its kind, name, parsed field names, per-field type hints, and the decoded rows. Produced by IsonGraphReader while scanning a document and consulted when rebuilding the object.
"
Class {
	#name : 'IsonGraphParsedBlock',
	#superclass : 'Object',
	#instVars : [
		'kind',
		'name',
		'fields',
		'hints',
		'rows'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'accessing' }
IsonGraphParsedBlock >> fields [

	^ fields
]

{ #category : 'accessing' }
IsonGraphParsedBlock >> fullName [

	^ kind , '.' , name
]

{ #category : 'accessing' }
IsonGraphParsedBlock >> hints [

	^ hints
]

{ #category : 'accessing' }
IsonGraphParsedBlock >> kind [

	^ kind
]

{ #category : 'accessing' }
IsonGraphParsedBlock >> name [

	^ name
]

{ #category : 'accessing' }
IsonGraphParsedBlock >> rows [

	^ rows
]

{ #category : 'initialization' }
IsonGraphParsedBlock >> setKind: aKind name: aName fields: aFieldArray hints: aHintArray [

	kind := aKind.
	name := aName.
	fields := aFieldArray.
	hints := aHintArray.
	rows := OrderedCollection new
]
