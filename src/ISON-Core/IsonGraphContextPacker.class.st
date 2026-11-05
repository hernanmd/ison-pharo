"
Fits the largest prefix of an already-prioritized collection into a token budget and answers one pinned ISON document stamped with its estimated token count and a content digest, so a consumer can cache the document and detect when it changes.

Entry point: `pack:total:` takes a block that answers the pack value (a Dictionary) for its first N items, and the full item count; it binary-searches for the largest N whose rendered document fits `budgetTokens` (estimated conservatively by IsonGraphTokenEstimator so the budget is not exceeded), then records estimatedTokens, overBudget and digest.

Options: budgetTokens:, strictGraphIds:, edgeRowSchema: (forwarded to the writer).
"
Class {
	#name : 'IsonGraphContextPacker',
	#superclass : 'Object',
	#instVars : [
		'budgetTokens',
		'strictGraphIds',
		'edgeRowSchema'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'accessing' }
IsonGraphContextPacker >> budgetTokens [

	^ budgetTokens ifNil: [ 8000 ]
]

{ #category : 'accessing' }
IsonGraphContextPacker >> budgetTokens: anInteger [

	budgetTokens := anInteger
]

{ #category : 'accessing' }
IsonGraphContextPacker >> edgeRowSchema: aSchema [

	edgeRowSchema := aSchema
]

{ #category : 'packing' }
IsonGraphContextPacker >> pack: aPackBlock total: aTotal [
	"aPackBlock answers the pack value (a Dictionary) for its first N prioritised items. Find the largest N
	 (at least 1) whose ISON document fits budgetTokens by the conservative IsonGraphTokenEstimator,
	 then stamp the value with budgetTokens, estimatedTokens, overBudget and a content digest (SHA-256 of
	 the document rendered without the digest) so a consumer can pin it and detect change. The fit is
	 measured WITH worst-case placeholders for those stamps, so the stamped document still fits.
	 Answers the final ISON text; deterministic for a fixed graph, seed and budget."

	| stamp fits lo hi n value text estimate |
	stamp := [ :v |
		         v at: 'budgetTokens' put: self budgetTokens.
		         v at: 'estimatedTokens' put: 9999999.
		         v at: 'overBudget' put: false.
		         v at: 'digest' put: ((1 to: 64)
				          collect: [ :i |
						          i odd
							          ifTrue: [ $a ]
							          ifFalse: [ $0 ] ]
				          as: String).
		         v ].
	fits := [ :k |
		        (IsonGraphTokenEstimator estimate:
			         (self render: (stamp value: (aPackBlock value: k))))
		        <= self budgetTokens ].
	aTotal <= 1
		ifTrue: [ n := 1 ]
		ifFalse: [
				(fits value: aTotal)
					ifTrue: [ n := aTotal ]
					ifFalse: [
							lo := 1.
							hi := aTotal - 1.
							[ lo < hi ] whileTrue: [
									| mid |
									mid := lo + hi + 1 // 2.
									(fits value: mid)
										ifTrue: [ lo := mid ]
										ifFalse: [ hi := mid - 1 ] ].
							n := lo ] ].
	value := stamp value: (aPackBlock value: n).
	estimate := IsonGraphTokenEstimator estimate: (self render: value).
	value at: 'estimatedTokens' put: estimate.
	value at: 'overBudget' put: estimate > self budgetTokens.
	value removeKey: 'digest'.
	text := self render: value.
	value
		at: 'digest'
		put: (SHA256 new hashMessage: text utf8Encoded) hex.
	^ self render: value
]

{ #category : 'packing' }
IsonGraphContextPacker >> render: aValue [

	| writer |
	writer := IsonGraphWriter new
		          strictGraphIds: (strictGraphIds ifNil: [ false ]);
		          yourself.
	edgeRowSchema ifNotNil: [ writer edgeRowSchema: edgeRowSchema ].
	^ writer documentFor: aValue
]

{ #category : 'accessing' }
IsonGraphContextPacker >> strictGraphIds: aBoolean [

	strictGraphIds := aBoolean
]
