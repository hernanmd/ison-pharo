Class {
	#name : 'IsonGraphTest',
	#superclass : 'TestCase',
	#category : 'ISON-Core-Tests',
	#package : 'ISON-Core-Tests'
}

{ #category : 'helpers' }
IsonGraphTest >> assertRoundTrip: anObject [
	"Write, read back, and compare under the IR-ISON equivalence; answer the document."

	| text back |
	text := IsonGraphWriter new documentFor: anObject.
	back := IsonGraphReader new read: text.
	self
		assert: (IsonGraphCodec equivalent: anObject to: back)
		description: [ 'round trip differs: ' , text ].
	^ text
]

{ #category : 'helpers' }
IsonGraphTest >> referenceRow: from kind: fromKind type: type to: to kind: toKind name: toName line: aLine [

	^ Dictionary new
		  at: 'fromId' put: from;
		  at: 'fromKind' put: fromKind;
		  at: 'edgeType' put: type;
		  at: 'toId' put: to;
		  at: 'toKind' put: toKind;
		  at: 'toName' put: toName;
		  at: 'toCitation' put: (Dictionary new
				   at: 'file' put: '/src/' , to , '.srw';
				   at: 'startLine' put: aLine;
				   yourself);
		  yourself
]

{ #category : 'tests' }
IsonGraphTest >> testInconsistentEndpointAttributesStayOnEdges [
	"If one node shows two different names, attributes cannot move to the node row: they stay per edge."

	| text |
	text := self assertRoundTrip: (Dictionary new
			         at: 'results' put: {
					         (self
						          referenceRow: 'a'
						          kind: 'Callable'
						          type: 'calls'
						          to: 'b'
						          kind: 'Callable'
						          name: 'one'
						          line: 5).
					         (self
						          referenceRow: 'c'
						          kind: 'Callable'
						          type: 'calls'
						          to: 'b'
						          kind: 'Callable'
						          name: 'two'
						          line: 5) };
			         yourself).
	self assert: (text includesSubstring: 'results:refs').
	self deny: (text includesSubstring: 'refs+').
	self assert: (text includesSubstring: 'toName')
]

{ #category : 'tests' }
IsonGraphTest >> testNestedShapesRoundTrip [
	"Lists, tables with nested lists (r column), objects that nest arrays (obj), flattened objects,
	 empty vs absent arrays, unflattenable floats and non-plain keys all survive."

	| text |
	text := self assertRoundTrip: (Dictionary new
			         at: 'ids' put: #( 'pkg.a' 'pkg.b' 'x y' );
			         at: 'empty' put: #(  );
			         at: 'mixed' put: { 1. 'two'. nil. true };
			         at: 'modules' put: {
					         (Dictionary new
						          at: 'screen' put: 'w1';
						          at: 'members' put: #( 'm1' 'm2' );
						          at: 'summary' put: (Dictionary new
								           at: 'loc' put: 3;
								           yourself);
						          yourself).
					         (Dictionary new
						          at: 'screen' put: 'w2';
						          at: 'members' put: #(  );
						          yourself).
					         (Dictionary new
						          at: 'screen' put: 'w3';
						          yourself) };
			         at: 'navigation' put: (Dictionary new
				          at: 'lifecycle' put: { (Dictionary new
						           at: 'name' put: 'open';
						           at: 'citation' put: (Dictionary new
								            at: 'file' put: '/src/w.srw';
								            at: 'startLine' put: 4;
								            yourself);
						           yourself) };
				          at: 'dispatch' put: #(  );
				          yourself);
			         at: 'citation' put: (Dictionary new
				          at: 'file' put: '/src/w.srw';
				          at: 'startLine' put: 1;
				          at: 'endLine' put: 9;
				          yourself);
			         at: 'tiny' put: 1.0e-12;
			         at: 'odd key' put: 'kept';
			         at: 'dotted.key' put: (Dictionary new
				          at: 'inner' put: 1;
				          yourself);
			         at: 'nested' put: {
				         { 1. 2 }.
				         { 3 } };
			         at: 'heterogeneous' put: {
				         (Dictionary new
					          at: 'a' put: 1;
					          yourself).
				         7 };
			         yourself).
	self assert: (text includesSubstring: 'list.result-ids').
	self assert: (text includesSubstring: 'tab.result-modules').
	self assert: (text includesSubstring: 'list.result-modules-members').
	self assert: (text includesSubstring: 'navigation:obj').
	self assert: (text includesSubstring: 'citation.file:file').
	self assert: (text includesSubstring: 'list.files')
]

{ #category : 'tests' }
IsonGraphTest >> testNodeRowsUseNodesBlocks [

	| text |
	text := self assertRoundTrip: (Dictionary new
			         at: 'count' put: 3;
			         at: 'results' put: {
					         (Dictionary new
						          at: 'id' put: 'p.w.f2';
						          at: 'kind' put: 'Callable';
						          at: 'name' put: 'f2';
						          yourself).
					         (Dictionary new
						          at: 'id' put: 'smtir://sql/table/t';
						          at: 'kind' put: 'Table';
						          at: 'name' put: 'T';
						          yourself).
					         (Dictionary new
						          at: 'id' put: 'p.w.f1';
						          at: 'kind' put: 'Callable';
						          at: 'name' put: 'f1';
						          yourself) };
			         yourself).
	self assert: (text includesSubstring: 'results:nodes').
	self assert: (text includesSubstring: 'nodes.Callable').
	self assert: (text includesSubstring: 'nodes.Table').
	"kind travels in the block name, not per row; readable ids are verbatim"
	self deny: (text includesSubstring: ' kind').
	self assert: (text includesSubstring: 'smtir://sql/table/t T').
	"rows inside a block are ordinal by id"
	self assert: (text indexOfSubCollection: 'p.w.f1')
		< (text indexOfSubCollection: 'p.w.f2')
]

{ #category : 'tests' }
IsonGraphTest >> testNodeTableAndReferencesShareOneGraph [
	"A document with its own node rows AND reference rows (the context-pack shape): edges point at the
	 document's node rows, endpoint attributes stay on the edges, and no endpoint rows are invented."

	| text |
	text := self assertRoundTrip: (Dictionary new
			         at: 'nodes' put: {
					         (Dictionary new
						          at: 'id' put: 'a';
						          at: 'kind' put: 'Callable';
						          at: 'name' put: 'A';
						          yourself).
					         (Dictionary new
						          at: 'id' put: 'b';
						          at: 'kind' put: 'Callable';
						          at: 'name' put: 'B';
						          yourself) };
			         at: 'references' put: { (Dictionary new
				          at: 'fromId' put: 'a';
				          at: 'fromKind' put: 'Callable';
				          at: 'edgeType' put: 'calls';
				          at: 'toId' put: 'b';
				          at: 'toKind' put: 'Callable';
				          at: 'toName' put: 'B';
				          yourself) };
			         yourself).
	self assert: (text includesSubstring: 'nodes:nodes').
	self assert: (text lines includes: 'nodes:nodes references:refs').
	self assert: (text includesSubstring: ':Callable:a :Callable:b').
	self assert: (text lines select: [ :l | l = 'a A' ]) size equals: 1
]

{ #category : 'tests' }
IsonGraphTest >> testNonObjectResultsAreWrapped [

	| text |
	text := self assertRoundTrip: #( 'a' 'b' ).
	self assert: (text beginsWith: '# ir-ison 1 wrapped').
	self assertRoundTrip: 42.
	self assert: (IsonGraphReader new read:
			 (IsonGraphWriter new documentFor: Dictionary new)) isNil
]

{ #category : 'tests' }
IsonGraphTest >> testOutputIsCanonical [
	"Same logical value, different construction order -> byte-identical document."

	| a b |
	a := Dictionary new.
	a
		at: 'z' put: 1;
		at: 'a' put: 'x';
		at: 'results' put: {
				(Dictionary new
					 at: 'id' put: 'n2';
					 at: 'kind' put: 'Callable';
					 yourself).
				(Dictionary new
					 at: 'id' put: 'n1';
					 at: 'kind' put: 'Callable';
					 yourself) }.
	b := OrderedDictionary new.
	b
		at: 'results' put: {
				(Dictionary new
					 at: 'kind' put: 'Callable';
					 at: 'id' put: 'n1';
					 yourself).
				(Dictionary new
					 at: 'kind' put: 'Callable';
					 at: 'id' put: 'n2';
					 yourself) };
		at: 'a' put: #x;
		at: 'z' put: 1.
	self
		assert: (IsonGraphWriter new documentFor: a)
		equals: (IsonGraphWriter new documentFor: b)
]

{ #category : 'tests' }
IsonGraphTest >> testReaderRejectsTruncatedDocument [

	| text cut |
	text := IsonGraphWriter new documentFor: (Dictionary new
			         at: 'ids' put: #( 'a' 'b' 'c' );
			         yourself).
	cut := text copyFrom: 1 to: (text lastIndexOf: $b).
	self should: [ IsonGraphReader new read: cut ] raise: Error
]

{ #category : 'tests' }
IsonGraphTest >> testReferenceRowsUseEdgeBlocksAndEndpointNodes [

	| text |
	text := self assertRoundTrip: (Dictionary new
			         at: 'resultKind' put: 'reference';
			         at: 'results' put: {
					         (self
						          referenceRow: 'a'
						          kind: 'Callable'
						          type: 'calls'
						          to: 'b'
						          kind: 'Callable'
						          name: 'bee'
						          line: 5).
					         (self
						          referenceRow: 'c'
						          kind: 'Callable'
						          type: 'calls'
						          to: 'b'
						          kind: 'Callable'
						          name: 'bee'
						          line: 5).
					         (self
						          referenceRow: 'a'
						          kind: 'Callable'
						          type: 'writes'
						          to: 'smtir://sql/table/t'
						          kind: 'Table'
						          name: 'T'
						          line: 1) };
			         yourself).
	self assert:
		(text includesSubstring: 'results:refs+toCitation+toName').
	self assert: (text includesSubstring: 'edges.calls').
	self assert: (text includesSubstring: 'edges.writes').
	self assert: (text includesSubstring: ':Callable:a :Callable:b').
	self assert:
		(text includesSubstring: ':Callable:a :Table:smtir://sql/table/t').
	"the shared target's name is written once, on its node row"
	self assert: (text occurrencesOf: $e) > 0.
	self assert:
		(text lines select: [ :l | l includesSubstring: ' bee' ]) size = 1
]

{ #category : 'tests' }
IsonGraphTest >> testScalarsNeedingQuotesRoundTrip [

	| text |
	text := self assertRoundTrip: (Dictionary new
			         at: 'spaced' put: 'a b';
			         at: 'numeric' put: '123';
			         at: 'floaty' put: '1.5';
			         at: 'expo' put: '1e5';
			         at: 'boolish' put: 'true';
			         at: 'nullish' put: '~';
			         at: 'refish' put: ':Kind:id';
			         at: 'hashy' put: '#comment';
			         at: 'dashes' put: '---';
			         at: 'empty' put: '';
			         at: 'quote' put: 'say "hi"';
			         at: 'multiline'
			         put:
				         'a' , (String with: Character lf) , 'b'
				         , (String with: Character tab) , 'c';
			         at: 'backslash'
			         put:
				         (String with: $a with: (Character value: 92) with: $b);
			         at: 'unicode'
			         put: 'caf' , (String with: (Character value: 233));
			         at: 'int' put: -42;
			         at: 'float' put: 0.25;
			         at: 'yes' put: true;
			         at: 'no' put: false;
			         yourself).
	self assert: (text beginsWith: '# ir-ison 1').
	self assert: (text includesSubstring: 'meta.result')
]

{ #category : 'tests' }
IsonGraphTest >> testStrictGraphIdsEscapeWhatIsonGraphRejects [

	| value readable strict |
	value := Dictionary new
		         at: 'results' put: { (Dictionary new
				          at: 'id' put: 'egl://a/b|c d%e';
				          at: 'kind' put: 'Type';
				          yourself) };
		         yourself.
	readable := IsonGraphWriter new documentFor: value.
	strict := IsonGraphWriter new
		          strictGraphIds: true;
		          documentFor: value.
	self assert: (readable includesSubstring: 'egl://a/b|c%20d%25e').
	self assert: (strict includesSubstring: 'egl%3A//a/b%7Cc%20d%25e').
	self assert: (IsonGraphCodec
			 equivalent: value
			 to: (IsonGraphReader new read: readable)).
	self assert: (IsonGraphCodec
			 equivalent: value
			 to: (IsonGraphReader new read: strict))
]
