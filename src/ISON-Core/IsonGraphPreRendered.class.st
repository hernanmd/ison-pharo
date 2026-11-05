"
Wraps an already-rendered ISON String so a caller can hand finished ISON text through a code path that would otherwise serialize an object again. `text` answers the stored document unchanged. Used for budget-fitted context packs that are rendered once and must pass through verbatim.
"
Class {
	#name : 'IsonGraphPreRendered',
	#superclass : 'Object',
	#instVars : [
		'text'
	],
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'initialization' }
IsonGraphPreRendered >> setText: aString [
	"An already-rendered ISON document (e.g. a budget-fitted context pack) that projectors must pass
	 through verbatim instead of serializing again."

	text := aString
]

{ #category : 'accessing' }
IsonGraphPreRendered >> text [

	^ text
]
