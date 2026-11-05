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
	"An already-rendered IR-ISON document (e.g. a budget-fitted context pack) that projectors must pass
	 through verbatim instead of serializing again."

	text := aString
]

{ #category : 'accessing' }
IsonGraphPreRendered >> text [

	^ text
]
