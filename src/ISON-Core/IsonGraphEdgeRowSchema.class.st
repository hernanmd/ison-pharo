"
Describes the contract by which a reference (edge) row names its source id, source kind, target id, target kind and edge type, plus the prefixes that mark endpoint-attribute keys. Makes the graph layout independent of any particular field vocabulary: a writer and reader configured with the same schema recognize and rebuild reference rows accordingly.

`IsonGraphEdgeRowSchema default` answers the neutral contract (source / sourceKind / target / targetKind / edgeType, with endpoint-attribute prefixes source and target, e.g. sourceName / targetCitation). A consumer whose rows use different key names supplies its own schema (directly, or via a subclass overriding the class-side default).

Key queries: structuralKeys, idKeyForRole:, kindKeyForRole:, edgeTypeKey, familyRoleOf:, attributeOf:, familyKeyForRole:attribute:.
"
Class {
	#name : 'IsonGraphEdgeRowSchema',
	#superclass : 'Object',
	#instVars : [
		'sourceIdKey',
		'sourceKindKey',
		'targetIdKey',
		'targetKindKey',
		'edgeTypeKey',
		'fromPrefix',
		'toPrefix'
	],
	#category : 'ISON-Core-Schema',
	#package : 'ISON-Core',
	#tag : 'Schema'
}

{ #category : 'instance creation' }
IsonGraphEdgeRowSchema class >> default [
	"The neutral IsonGraph edge-row contract: reference rows keyed source/target (ids), sourceKind/targetKind, edgeType; endpoint attributes prefixed source/target (sourceName, targetCitation). No producer-specific vocabulary."

	^ self new
		  sourceIdKey: 'source';
		  sourceKindKey: 'sourceKind';
		  targetIdKey: 'target';
		  targetKindKey: 'targetKind';
		  edgeTypeKey: 'edgeType';
		  fromPrefix: 'source';
		  toPrefix: 'target';
		  yourself
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> attributeOf: aKey [
	"The bare attribute name an endpoint family key carries: sourceName -> name, targetCitation -> citation.
	 The role's prefix is stripped and the next char lowercased."

	| prefix rest |
	prefix := (self roleOf: aKey) = 'from'
		          ifTrue: [ fromPrefix ]
		          ifFalse: [ toPrefix ].
	rest := aKey allButFirst: prefix size.
	^ rest first asLowercase asString , rest allButFirst
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> edgeTypeKey [

	^ edgeTypeKey
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> edgeTypeKey: aString [

	edgeTypeKey := aString
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> familyKeyForRole: aRole attribute: anAttribute [
	"Rebuild an endpoint family key from a role ('from'/'to') and a bare attribute (the inverse of
	 attributeOf:). Used by the reader to reconstruct rows: role 'from' + attribute 'citation' -> sourceCitation."

	| prefix |
	prefix := aRole = 'from'
		          ifTrue: [ fromPrefix ]
		          ifFalse: [ toPrefix ].
	^ prefix
	  ,
	  (anAttribute first asUppercase asString , anAttribute allButFirst)
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> familyRoleOf: aKey [
	"The endpoint role ('from'/'to') of aKey IF it is an endpoint-attribute family key, else nil. Structural
	 keys (source/sourceKind/target/targetKind/edgeType) are never families even when their text matches a
	 prefix pattern (e.g. default sourceKind vs fromPrefix 'source'). This is the one entry point callers
	 should use to classify a row key."

	(self structuralKeys includes: aKey) ifTrue: [ ^ nil ].
	^ self roleOf: aKey
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> fromPrefix [

	^ fromPrefix
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> fromPrefix: aString [

	fromPrefix := aString
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> idKeyForRole: aRole [

	^ aRole = 'from'
		  ifTrue: [ sourceIdKey ]
		  ifFalse: [ targetIdKey ]
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> isAttribute: aKey withPrefix: aPrefix [
	"True when aKey is aPrefix immediately followed by an uppercase letter (an endpoint attribute like
	 sourceName / targetCitation), so the bare prefix or a structural key is not mistaken for an attribute."

	^ aKey size > aPrefix size and: [
			  (aKey beginsWith: aPrefix) and: [
				  (aKey at: aPrefix size + 1) isUppercase ] ]
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> kindKeyForRole: aRole [

	^ aRole = 'from'
		  ifTrue: [ sourceKindKey ]
		  ifFalse: [ targetKindKey ]
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> roleOf: aKey [
	"'from' if aKey is a source-endpoint attribute (fromPrefix + Capitalised rest), 'to' for a target
	 attribute, else nil. Structural keys are NOT attributes — callers exclude them first via structuralKeys."

	(self isAttribute: aKey withPrefix: fromPrefix) ifTrue: [ ^ 'from' ].
	(self isAttribute: aKey withPrefix: toPrefix) ifTrue: [ ^ 'to' ].
	^ nil
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> sourceIdKey [

	^ sourceIdKey
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> sourceIdKey: aString [

	sourceIdKey := aString
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> sourceKindKey [

	^ sourceKindKey
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> sourceKindKey: aString [

	sourceKindKey := aString
]

{ #category : 'contract' }
IsonGraphEdgeRowSchema >> structuralKeys [
	"The five keys that name an edge's endpoints and type — excluded from the endpoint-attribute scan."

	^ {
		  sourceIdKey.
		  sourceKindKey.
		  targetIdKey.
		  targetKindKey.
		  edgeTypeKey }
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> targetIdKey [

	^ targetIdKey
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> targetIdKey: aString [

	targetIdKey := aString
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> targetKindKey [

	^ targetKindKey
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> targetKindKey: aString [

	targetKindKey := aString
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> toPrefix [

	^ toPrefix
]

{ #category : 'accessing' }
IsonGraphEdgeRowSchema >> toPrefix: aString [

	toPrefix := aString
]
