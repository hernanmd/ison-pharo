"
Answers a cheap, dependency-free, deliberately conservative estimate of how many LLM tokens a string will cost, without a byte-pair-encoding vocabulary.

Entry point (class side): `estimate:` counts letter runs as ceil(length / 9), digit runs as ceil(length / 3), every other non-blank character and every newline as 1, and spaces as free. Calibrated to never under-count on representative output, which is what a budget check needs. Used by IsonGraphContextPacker.
"
Class {
	#name : 'IsonGraphTokenEstimator',
	#superclass : 'Object',
	#category : 'ISON-Core',
	#package : 'ISON-Core'
}

{ #category : 'estimating' }
IsonGraphTokenEstimator class >> estimate: aString [
	"Conservative o200k_base token estimate without a BPE vocabulary: letter runs cost ceil(len/9), digit
	 runs ceil(len/3), every other non-blank character and every newline 1; spaces are free. Calibrated by
	 a calibration harness on representative IsonGraph
	 outputs: estimate/actual stayed within [1.07, 1.33] - it never under-counts on that corpus, so a
	 budget computed with it is not exceeded."

	| n i size |
	n := 0.
	i := 1.
	size := aString size.
	[ i <= size ] whileTrue: [
			| c start |
			c := aString at: i.
			(c asInteger < 128 and: [ c isLetter ])
				ifTrue: [
						start := i.
						[
							i <= size and: [
								(aString at: i) asInteger < 128 and: [
									(aString at: i) isLetter ] ] ] whileTrue: [ i := i + 1 ].
						n := n + (i - start + 8 // 9) ]
				ifFalse: [
						c isDigit
							ifTrue: [
									start := i.
									[ i <= size and: [ (aString at: i) isDigit ] ] whileTrue: [
										i := i + 1 ].
									n := n + (i - start + 2 // 3) ]
							ifFalse: [
									(c = Character space or: [ c = Character tab ]) ifFalse: [
										n := n + 1 ].
									i := i + 1 ] ] ].
	^ n
]
