Class {
	#name : 'BaselineOfISONCore',
	#superclass : 'BaselineOf',
	#category : 'BaselineOfISONCore',
	#package : 'BaselineOfISONCore'
}

{ #category : 'baselines' }
BaselineOfISONCore >> baseline: spec [
  <baseline>
	spec
		for: #(common)
		do: [ 
			spec 
				package: 'ISON-Core';
				package: 'ISON-Core-Tests'	with: [ spec requires: #(ISON-Core) ].
			spec 
				group: 'Core' with: #('ISON-Core');
				group: 'Tests' with: #('ISON-Core' 'ISON-Core-Tests');
				group: 'default' with: #('Core' 'Tests') ]
]
