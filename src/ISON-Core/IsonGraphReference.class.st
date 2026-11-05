"
Represents a node reference written in ISON as `:<kind>:<id>` (for example :person:1). Holds a kind and an id; `isonString` answers the serialized form. Equality and hashing are by kind and id, so references can be used as keys. Used in edges.<edgeType> blocks for the source and target cells.
"
Class {
	#name : 'IsonGraphReference',
	#superclass : 'Object',
	#instVars : [
		'kind',
		'id'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'comparing' }
IsonGraphReference >> = anObject [

	^ self class == anObject class and: [
		  kind = anObject kind and: [ id = anObject id ] ]
]

{ #category : 'comparing' }
IsonGraphReference >> hash [

	^ kind hash bitXor: id hash
]

{ #category : 'accessing' }
IsonGraphReference >> id [

	^ id
]

{ #category : 'printing' }
IsonGraphReference >> isonString [
	"ISONGraph node reference `:Kind:id` (written unquoted; ids carrying whitespace never get here)."

	^ kind ifNil: [ ':' , id ] ifNotNil: [ ':' , kind , ':' , id ]
]

{ #category : 'accessing' }
IsonGraphReference >> kind [

	^ kind
]

{ #category : 'printing' }
IsonGraphReference >> printOn: aStream [

	aStream nextPutAll: self isonString
]

{ #category : 'initialization' }
IsonGraphReference >> setKind: aKindString id: anIdString [

	kind := aKindString.
	id := anIdString
]
