Class {
	#name : 'IsonGraphColumn',
	#superclass : 'Object',
	#instVars : [
		'name',
		'hint',
		'cells'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'accessing' }
IsonGraphColumn >> cells [

	^ cells
]

{ #category : 'printing' }
IsonGraphColumn >> fieldString [
	"The header token: `name` or `name:hint` (ISON field type-annotation syntax)."

	^ hint ifNil: [ name ] ifNotNil: [ name , ':' , hint ]
]

{ #category : 'accessing' }
IsonGraphColumn >> hint [

	^ hint
]

{ #category : 'accessing' }
IsonGraphColumn >> name [

	^ name
]

{ #category : 'initialization' }
IsonGraphColumn >> setName: aName hint: aHintOrNil cells: anArray [

	name := aName.
	hint := aHintOrNil.
	cells := anArray
]
