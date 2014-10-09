log = (x)-> console.log(x)

mixOf = (base, mixins...) ->
	class Mixed extends base
		for mixin in mixins by -1 # earlier mixins override later ones
			for name, method of mixin::
				Mixed::[name] = method
	Mixed

class Resource
	construct: (@destroy)->
		@holdLevel = 0

	hold: ->
		@holdLevel++

	release: ->
		if --@holdLevel is 0
			@destroy()
		@destroy = undefined

class Evented
	listenEvent: (name, fn)->
		@eventListeners ?= {}
		@eventListeners[name] ?= lastId: 0, funcs: []
		index = @eventListeners[name].lastId++
		@eventListeners[name].funcs[index] = fn
		new Resource => @unlisten name, index

	unlistenEvent: (name, fnOrIndex)->
		@eventListeners ?= {}
		listeners = @eventListeners[name]
		if listeners?
			if typeof fnOrIndex is 'number'
				delete listeners.funcs[fnOrIndex]
			else
				for index, fn of listeners.funcs when fn is fnOrIndex
					delete listeners.funcs[i]
					break

	fireEvent: (name, event = {}, returnEvent = no)->
		$extend event,
			name: name
			_isPropagationPrevented: no
			_isCanceled: no
			cancel: -> @_isCanceled = yes
			preventPropagation: -> @_isPropagationPrevented = yes

		isOk = yes
		if @eventListeners?[name]?
			for index, fn of @eventListeners[name].funcs when fn?
				break if event._isPropagationPrevented
				result = fn.call @, event
				isOk = no if result is no or event._isCanceled

		if returnEvent then event else isOk

class Sized
	getSize: (type, axis)->
		@['get' + type + axis]()

	calcSize: (axis)->
		verb = @['getRaw' + axis]()
		isString = $.type(verb) is 'string'
		if verb is 'auto'
			Misc.sum(child.getSize 'Outer', axis for child in @getChildrenElements())
		else if $.type(verb) is 'number'
			verb
		else if isString and verb.indexOf('px') > -1
			parseInt verb 
		else if isString and verb.indexOf('%') > -1 
			percents = parseInt verb
			parent = @getParentElement()
			innerSpace = if parent? then parent.getSize 'Inner', axis else 0

			Math.round(innerSpace * percents / 100) -
			@getExtraOffsetBefore() -
			@getExtraOffsetAfter()
		else if isString and verb.indexOf('part') > -1 
			parts = parseInt verb
			totalParts = 0
			parent = @getParentElement()
			remainingSpace = if parent? then parent.getSize 'Inner', axis else 0
			if parent?
				siblings = parent.getChildrenElements()
				for sibling in siblings
					siblingVerb = sibling.getSize 'Raw', axis
					if $.type(siblingVerb) is 'string' and siblingVerb.indexOf('part') > -1
						totalParts += parseInt siblingVerb 
					else
						remainingSpace -= sibling.getSize 'Outer', axis
				
			Math.round(remainingSpace * parts / totalParts) -
			@getExtraOffsetBefore() -
			@getExtraOffsetAfter()

	getParentElement: ->

	getChildrenElements: ->
		[]

	getRawHeight: ->
		'auto'

	getInnerHeight: ->
		@calcSize 'Height'

	getOuterHeight: ->
		@getInnerHeight() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getExtraOffsetBefore: ->
		0

	getExtraOffsetAfter: ->
		0

	doesSizeDependOnParent: ->
		verb = @getRawHeight()
		$.type(verb) is 'string' and (verb.indexOf('part') > -1 or verb.indexOf('%') > -1)

class Timeline extends Evented
	constructor: (container, config = {}, items = [])->
		@container = new Timeline.Container $(container), @
		@config = $.extend yes, @getDefaultConfig(), config

		@root = @createElement 'Root'
		@sidebar = @createElement 'Sidebar'
		@ruler = @createElement 'Ruler'
		@field = @createElement 'Field'
		
		@ranges = []
		@initialAddRange range for range in @config.ranges
		@sortRanges()

		@groups = []
		@initialAddGroup group for group in @config.groups
		@sortGroups()

		@lines = []
		@initialAddLine line for line in @config.lines
		@sortLines()

		@dashRules = []
		@initialAddDashRule rule for rule in @config.dashRules
		@sortDashRules()

		@items = []
		@initialAddItem item for item in items

		@checkVerticalFitting()

		@root.build()

	createElement: (type, data = {})->
		new @constructor[type] @, data 

	initialAddRange: (range)->
		for elseRange in @ranges
			if range.from < elseRange.raw.to and range.to > elseRange.raw.from 
				throw 'Can\'t add range overlapping existing one'

		@ranges.push @createElement 'Range', range

	sortRanges: ->
		@ranges = @ranges.sort (a, b)->
			a.raw.from - b.raw.from

	initialAddGroup: (group)->
		for elseGroup in @groups
			if elseGroup.raw.id is group.id
				throw 'Can\'t add group with same id as existing one has'

		@groups.push @createElement 'Group', group

	sortGroups: ->
		@groups = @groups.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	initialAddLine: (line)->
		for elseLine in @lines
			if elseLine.raw.id is line.id
				throw 'Can\'t add line with same id as existing one has'

		@lines.push @createElement 'Line', line

	sortLines: ->
		@lines = @lines.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	initialAddDashRule: (rule)->
		for elseRule in @dashRules
			if elseRule.id is rule.id
				throw 'Can\'t add dash rule with same id as existing one has'

		@dashRules.push rule

	sortDashRules: ->
		@dashRules = @dashRules.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	initialAddItem: (obj)->
		item = @createElement 'Item', obj
		unless item.isValid()
			throw 'Can\'t add item due to its invalidity'

		@items.push item 

	getDefaultConfig: ->
		field:
			render: null
			place: null
		ruler:
			isVisible: yes
			position: 'top'
			height: 50
			render: null
			place: null
		sidebar:
			isVisible: yes
			position: 'left'
			width: 100
			render: null
			place: null
		range:
			extraOffset: 
				before: 5
				after: 15
			render: null
			place: null
			renderAtRuler: null
			placeAtRuler: null
		group:
			height: 'auto'
			extraOffset:
				before: 5
				after: 5
			render: null
			place: null
		line:
			height: 50
			extraOffset:
				before: 5
				after: 10
			render: null
			place: null
			renderAtSidebar: null
			placeAtSidebar: null
		item:
			isDraggable: yes
			canCrossRanges: yes
			render: null
			place: null
		dash:
			render: null
			place: null
		scale: 1
		snapResolution: 1
		height: '100%'
		dashRules: []
		ranges: []
		groups: []
		lines: []

	calcDashes: ->
		dashes = []
		for dashRule in @dashRules 
			for range in @ranges
				if dashRule.type is 'every'
					dashes = dashes.concat @calcDashesEvery range, dashRule
		
		map = {}
		map[dash.time] = dash for dash in dashes when !map[dash.time]?

		dashes = []
		dashes.push @createElement 'Dash', dash for time, dash of map
		dashes

	calcDashesEvery: (range, rule)->
		dashes = []
		time = range.raw.from
		while time < range.raw.to
			dashes.push {time, rule}
			time += rule.step
		dashes

	getGroupById: (groupId)->
		for group in @groups
			if group.raw.id is groupId
				return group

	getRangeByTime: (time)->
		for range in @ranges
			if range.raw.from <= time < range.raw.to
				return range

	getRangeByOffset: (offset)->
		for range in @ranges
			rangeStart = range.getOffset() + range.getInternalOffset(range.raw.from)
			rangeEnd = rangeStart + range.getInnerWidth()
			if rangeStart <= offset < rangeEnd
				return range

	getLineById: (lineId)->
		for line in @lines
			if line.raw.id is lineId
				return line

	getLineByVerticalOffset: (group, verticalOffset)->
		for line in group.getLines()
			lineStart = line.getVerticalOffset() + line.getInternalVerticalOffset()
			lineEnd = lineStart + line.getInnerHeight()
			if lineStart <= verticalOffset < lineEnd
				return line

	getTime: (offset)->
		range = @getRangeByOffset offset
		if range?
			range.getTimeByOffset offset

	getOffset: (time)->	
		if time?
			range = @getRangeByTime time
			if range?
				range.getOffset() + range.getInternalOffset(time)

	approxTime: (time, allowPostRange = no)->
		if time?
			resolution = @config.snapResolution
			approxed = Math.round(time / resolution) * resolution
			if (allowPostRange and @getRangeByTime approxed - 1) or @getRangeByTime approxed
				approxed
			else
				approxed = Math.ceil(time / resolution) * resolution
				if @getRangeByTime approxed
					approxed
				else
					approxed = Math.floor(time / resolution) * resolution
					approxed if @getRangeByTime approxed

	checkVerticalFitting: ->
		if @root.getRawHeight() is 'auto'
			if @ruler.doesSizeDependOnParent()
				throw 'In timeline auto-height mode the ruler size must not be specified in parts of remaining space' 
			for group in @groups when group.doesSizeDependOnParent()
				throw 'In timeline auto-height mode there must not be groups with size specified in parts of remaining space' 

class Misc
	@addDom: (name, $container)->
		$element = $('<div />').addClass "tl-#{name}"
		if $container
			$element.appendTo @getScrollContainer $container
		$element

	@scrollize: ($element, axis, pairs = [])->
		$inner = @addDom 'scroll-inner', $element
		$element.data 'scroll-inner', $inner

		config =
			theme: 'dark-2'
			autoHideScrollbar: yes
			axis: axis
			scrollInertia: 0
			mouseWheel:
				scrollAmount: 30
			callbacks: {}

		config.mouseWheel.axis = 'x' if axis is 'xy'

		if pairs.length
			config.callbacks.whileScrolling = ->
				for pair in pairs
					$targets = pair.getTarget()
					if $targets?.length
						position = {}
						position.x = @mcs.left + 'px' if pair.axis.indexOf('x') > -1
						position.y = @mcs.top + 'px' if pair.axis.indexOf('y') > -1

						$.each $targets, ->
							$(@).mCustomScrollbar 'scrollTo', position,
								scrollInertia: 0
								timeout: 0
								callbacks: no

		$element.mCustomScrollbar config

	@getScrollContainer: ($element)->
		$inner = $element.data 'scroll-inner'

		if $inner?.length
			$inner
		else
			$element

	@setInnerSize: ($element, size)->
		css = {}
		css.width = size.x if size.x
		css.height = size.y if size.y
		@getScrollContainer($element).css css
		$element.mCustomScrollbar 'update'

	@sum: (array)->
		sum = 0
		sum += value for value in array
		sum


class Timeline.Element extends Sized
	constructor: (@timeline, @raw = {})->
		@className = @getClassName()
		@init()

	getClassName: ->
		''

	init: ->

	cfg: ->
		@timeline.config[@className] ? {}

	getRawHeight: ->
		@raw.height ? @cfg().height ? 'auto'

	getExtraOffsetBefore: ->
		@raw.extraOffsetBefore ? @cfg().extraOffset?.before ? 0

	getExtraOffsetAfter: ->
		@raw.extraOffsetAfter ? @cfg().extraOffset?.after ? 0

class Timeline.Container extends Sized
	constructor: (@$dom, @timeline)->

	getRawHeight: ->
		0

	getInnerHeight: ->
		@$dom.innerHeight()

	getChildrenElements: ->
		[@timeline]

class Timeline.Root extends Timeline.Element
	getClassName: ->
		'root'

	build: ->
		@$dom = Misc.addDom 'root', @timeline.container.$dom
		@render()
		@place()

		@timeline.sidebar.build()
		@timeline.ruler.build()
		@timeline.field.build()

	render: ->

	place: ->
		@$dom.css
			height: @getInnerHeight()

	getParentElement: ->
		@timeline.container

	getChildrenElements: ->
		@timeline.groups.concat [@timeline.ruler]

	getRawHeight: ->
		@timeline.config.height ? 'auto'

class Timeline.Sidebar extends Timeline.Element
	getClassName: ->
		'sidebar'

	isVisible: ->
		@raw.isVisible ? @cfg().isVisible ? yes

	getOuterWidth: ->
		if @isVisible()
			@getInnerWidth()
		else
			0

	getInnerWidth: ->
		if @isVisible()
			@raw.width ? @cfg().width ? 100
		else
			0

	build: ->
		@$dom = Misc.addDom 'sidebar', @timeline.root.$dom
		@render()
		@place()

		@buildGroups()

	render: ->
		(@raw.render ? @cfg().render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().place ? @constructor.place).call @

	@place: ->
		@$dom.css if @timeline.config.ruler.position is 'top'
			top: @timeline.ruler.getOuterHeight()
			bottom: 0
		else 
			top: 0
			bottom: @timeline.ruler.getOuterHeight()

		@$dom.css if @cfg().position is 'left'
			left: 0
			right: 'auto'
		else 
			left: 'auto'
			right: 0

		@$dom.css 
			width: @getInnerWidth()

	buildGroups: ->
		group.buildAtSidebar() for group in @timeline.groups

class Timeline.Ruler extends Timeline.Element
	getClassName: ->
		'ruler'

	isVisible: ->
		@raw.isVisible ? @cfg().isVisible ? yes

	getRawHeight: ->
		if @isVisible() then super() else 0

	getExtraOffsetBefore: ->
		if @isVisible() then super() else 0

	getExtraOffsetAfter: ->
		if @isVisible() then super() else 0

	getParentElement: ->
		@timeline.root

	build: ->
		@$dom = Misc.addDom 'ruler', @timeline.root.$dom
		Misc.scrollize @$dom, 'x', [{axis: 'x', getTarget: => group.$dom for group in @timeline.groups}]
		@render()
		@place()
		
		@buildRanges()
		@buildDashes()

	render: ->
		(@raw.render ? @cfg().render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().place ? @constructor.place).call @

	@place: ->
		@$dom.css if @timeline.config.sidebar.position is 'left'
			left: @timeline.sidebar.getOuterWidth()
			right: 0
		else 
			left: 0
			right: @timeline.sidebar.getOuterWidth()

		@$dom.css if @cfg().position is 'top'
			top: 0
			bottom: 'auto'
		else 
			top: 'auto'
			bottom: 0

		@$dom.css 
			height: @timeline.ruler.getInnerHeight()

		Misc.setInnerSize @$dom, 
			x: Misc.sum(range.getOuterWidth() for range in @timeline.ranges)
			y: @timeline.ruler.getInnerHeight()

	buildRanges: ->
		range.buildAtRuler() for range in @timeline.ranges

	buildDashes: ->
		dash.buildAtRuler() for dash in @timeline.calcDashes()

class Timeline.Field extends Timeline.Element
	getClassName: ->
		'field'

	build: ->
		@$dom = Misc.addDom 'field', @timeline.root.$dom
		@render()
		@place()

		@buildGroups()

	render: ->
		(@raw.render ? @cfg().render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().place ? @constructor.place).call @

	@place: ->
		@$dom.css if @timeline.config.ruler.position is 'top'
			top: @timeline.ruler.getOuterHeight()
			bottom: 0
		else 
			top: 0
			bottom: @timeline.ruler.getOuterHeight()

		@$dom.css if @timeline.config.sidebar.position is 'left'
			left: @timeline.sidebar.getOuterWidth()
			right: 0
		else 
			left: 0
			right: @timeline.sidebar.getOuterWidth()

	buildGroups: ->
		group.build() for group in @timeline.groups

class Timeline.Group extends Timeline.Element
	getClassName: ->
		'group'

	getLines: ->
		line for line in @timeline.lines when line.raw.groupId is @raw.id

	getVerticalOffset: ->
		x = Misc.sum(
			for elseGroup in @timeline.groups
				break if elseGroup.raw.id is @raw.id
				elseGroup.getOuterHeight() 
		)

	getParentElement: ->
		@timeline.root

	getChildrenElements: ->
		@getLines()

	build: ->
		@$dom = Misc.addDom 'group', @timeline.field.$dom
		Misc.scrollize @$dom, 'xy', [
			{axis: 'x', getTarget: => 
				targets = (elseGroup.$dom for elseGroup in @timeline.groups when elseGroup isnt @)
				targets.push @timeline.ruler.$dom if @timeline.ruler.$dom?
				targets
			},
			{axis: 'y', getTarget: => @$sidebarDom ? null}
		]
		@render()
		@place()

		@buildLines()
		@buildRanges()
		@buildDashes()
		@buildItems()

	render: ->
		(@raw.render ? @cfg().render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().place ? @constructor.place).call @

	@place: ->
		@$dom.css
			top : @getVerticalOffset()
			height: @getInnerHeight()

		Misc.setInnerSize @$dom, 
			x: Misc.sum(range.getOuterWidth() for range in @timeline.ranges)
			y: Misc.sum(line.getOuterHeight() for line in @getLines())

	buildLines: ->
		line.build() for line in @getLines()

	buildRanges: ->
		range.build @ for range in @timeline.ranges

	buildDashes: ->
		dash.build @ for dash in @timeline.calcDashes()

	buildItems: ->
		item.build() for item in @timeline.items when item.getLine().raw.groupId is @raw.id

	buildAtSidebar: ->
		@$sidebarDom = Misc.addDom 'group', @timeline.sidebar.$dom
		Misc.scrollize @$sidebarDom, 'y', [{axis: 'y', getTarget: => @$dom}]
		@renderAtSidebar()
		@placeAtSidebar()

		@buildLinesAtSidebar()

	renderAtSidebar: ->
		(@raw.renderAtSidebar ? @cfg().renderAtSidebar ? @constructor.renderAtSidebar).call @

	@renderAtSidebar: ->

	placeAtSidebar: ->
		(@raw.placeAtSidebar ? @cfg().placeAtSidebar ? @constructor.placeAtSidebar).call @

	@placeAtSidebar: ->
		@$sidebarDom.css
			top : @getVerticalOffset()
			height: @getInnerHeight()

		Misc.setInnerSize @$sidebarDom,
			x: @timeline.sidebar.getInnerWidth()
			y: Misc.sum(line.getOuterHeight() for line in @getLines())

	buildLinesAtSidebar: ->
		line.buildAtSidebar() for line in @getLines()

class Timeline.Range extends Timeline.Element
	getClassName: ->
		'range'

	init: ->
		@$doms = []

	getOffset: ->
		Misc.sum(
			for elseRange in @timeline.ranges when elseRange.raw.from < @raw.from
				elseRange.getOuterWidth() 
		)

	getInternalOffset: (time)->
		@getExtraOffsetBefore() +
		Math.ceil(time / @timeline.config.scale) - Math.ceil(@raw.from / @timeline.config.scale)

	getInnerWidth: ->
		Math.ceil(@raw.to / @timeline.config.scale) - Math.ceil(@raw.from / @timeline.config.scale)

	getOuterWidth: ->
		@getInnerWidth() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getExtraOffsetBefore: ->
		@raw.extraOffsetBefore ? @cfg().extraOffset.before

	getExtraOffsetAfter: ->
		@raw.extraOffsetAfter ? @cfg().extraOffset.after

	getTimeByOffset: (offset)->
		@getTimeByInternalOffset(offset - @getOffset() - @getExtraOffsetBefore())

	getTimeByInternalOffset: (internalOffset)->
		@raw.from + internalOffset * @timeline.config.scale

	build: (group)->
		$dom = Misc.addDom 'range', group.$dom
		@$doms.push $dom
		@render $dom
		@place $dom

	render: ($dom)->
		(@raw.render ? @cfg().render ? @constructor.render).call @, $dom

	@render: ($dom)->

	place: ($dom)->
		(@raw.place ? @cfg().place ? @constructor.place).call @, $dom

	@place: ($dom)->
		$dom.css
			left: @getOffset()
			width: @getInnerWidth()

	buildAtRuler: ->
		@$rulerDom = Misc.addDom 'range', @timeline.ruler.$dom
		@renderAtRuler()
		@placeAtRuler()

	renderAtRuler: ->
		(@raw.renderAtRuler ? @cfg().renderAtRuler ? @constructor.renderAtRuler).call @

	@renderAtRuler: ->
		from = moment.unix(@raw.from).format('DD.MM.YYYY HH:mm:ss')
		to = moment.unix(@raw.to).format('DD.MM.YYYY HH:mm:ss')
		@$rulerDom.empty().append Misc.addDom('heading').text "#{from} — #{to}"

	placeAtRuler: ->
		(@raw.placeAtRuler ? @cfg().placeAtRuler ? @constructor.placeAtRuler).call @

	@placeAtRuler: ->
		@$rulerDom.css
			left: @getOffset()
			width: @getInnerWidth()


class Timeline.Dash extends Timeline.Element
	getClassName: ->
		'dash'

	init: ->
		@$doms = []

	build: (group)->
		$dom = Misc.addDom 'dash', group.$dom
		$dom.addClass "id-#{@raw.rule.id}"
		@$doms.push $dom
		@render $dom
		@place $dom

	render: ($dom)->
		(@raw.render ? @cfg().render ? @constructor.render).call @, $dom

	@render: ($dom)->
		$dom.empty()

	place: ($dom)->
		(@raw.place ? @cfg().place ? @constructor.place).call @, $dom

	@place: ($dom)->
		offset = @timeline.getOffset @raw.time
		if offset?
			$dom.css left: offset

	buildAtRuler: (dash)->
		@$rulerDom = Misc.addDom 'dash', @timeline.ruler.$dom
		@$rulerDom.addClass "id-#{@raw.rule.id}"
		@renderAtRuler()
		@placeAtRuler()

	renderAtRuler: ->
		(@raw.renderAtRuler ? @cfg().renderAtRuler ? @constructor.renderAtRuler).call @

	@renderAtRuler: ->

	placeAtRuler: ->
		(@raw.placeAtRuler ? @cfg().placeAtRuler ? @constructor.placeAtRuler).call @

	@placeAtRuler: ->
		offset = @timeline.getOffset @raw.time
		if offset?
			@$rulerDom.css left: offset

class Timeline.Line extends Timeline.Element
	getClassName: ->
		'line'

	getVerticalOffset: ->
		Misc.sum(
			for elseLine in @timeline.lines when elseLine.raw.groupId is @raw.groupId
				break if elseLine.raw.id is @raw.id
				elseLine.getOuterHeight() 
		)

	getInternalVerticalOffset: ->
		@getExtraOffsetBefore()	

	getParentElement: ->
		@getGroup()

	getRawHeight: ->
		@raw.height ? @cfg().height ? 0

	getInnerHeight: ->
		@calcSize 'Height'

	getOuterHeight: ->
		@getInnerHeight() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getGroup: ->
		@timeline.getGroupById @raw.groupId

	getExtraOffsetBefore: ->
		@raw.extraOffsetBefore ? @cfg().extraOffset.before

	getExtraOffsetAfter: ->
		@raw.extraOffsetAfter ? @cfg().extraOffset.after

	build: ->
		@$dom = Misc.addDom 'line', @getGroup().$dom
		@render()
		@place()

	render: ->
		(@raw.render ? @cfg().render ? @constructor.render).call @

	@render: ->
		@$dom.empty()

	place: ->
		(@raw.place ? @cfg().place ? @constructor.place).call @

	@place: ->
		@$dom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

	buildAtSidebar: ->
		@$sidebarDom = Misc.addDom 'line', @getGroup().$sidebarDom
		@renderAtSidebar()
		@placeAtSidebar()

	renderAtSidebar: ->
		(@raw.renderAtSidebar ? @cfg().renderAtSidebar ? @constructor.renderAtSidebar).call @

	@renderAtSidebar: ->
		@$sidebarDom.empty().append Misc.addDom('heading').text @raw.id

	placeAtSidebar: ->
		(@raw.placeAtSidebar ? @cfg().placeAtSidebar ? @constructor.placeAtSidebar).call @

	@placeAtSidebar: ->
		@$sidebarDom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

class Timeline.Item extends Timeline.Element
	getClassName: ->
		'item'

	getLine: ->
		@timeline.getLineById @raw.lineId

	getDuration: ->
		@raw.to - @raw.from

	isDraggable: ->
		@raw.isDraggable ? @cfg().isDraggable ? yes

	canCrossRanges: ->
		@raw.canCrossRanges ? @cfg().canCrossRanges ? yes

	build: ->
		@$dom = Misc.addDom 'item', @getLine().getGroup().$dom
		@render()
		@place()
		@makeDraggable()
		@makeResizeableLeft()
		@makeResizeableRight()

	render: ->
		(@raw.render ? @cfg().render ? @constructor.render).call @

	@render: ->
		@$dom.empty().append Misc.addDom('text').text @raw.text

	place: ->
		(@raw.place ? @cfg().place ? @constructor.place).call @

	@place: ->
		line = @getLine()
		offset = @timeline.getOffset @raw.from
		@$dom.css
			top: line.getVerticalOffset() + line.getInternalVerticalOffset()
			height: line.getInnerHeight()
			left: offset
			width: @timeline.getOffset(@raw.to-1) - offset
	
	makeDraggable: ->
		@$dragHint = null
		modified = null

		@$dom.draggable
			helper: =>
				Misc.addDom('drag-helper').css
					width: @$dom.css 'width'
					height: @$dom.css 'height'
			start: (e, ui)=>
				@$dragHint = Misc.addDom 'drag-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
			stop: (e, ui)=>
				@$dragHint.remove()
				modified = null
			drag: (e, ui)=>
				group = @getLine().getGroup()
				dragInfo = 
					parentOffset: Misc.getScrollContainer(group.$dom).offset()
					event: e
					ui: ui
				
				@renderDragHint dragInfo
				@placeDragHint dragInfo
				
				duration = @getDuration()
				modified.raw.from = @timeline.approxTime @timeline.getTime dragInfo.ui.position.left
				modified.raw.to = modified.raw.from + duration
				newLine = @timeline.getLineByVerticalOffset group, dragInfo.event.pageY - dragInfo.parentOffset.top
				modified.raw.lineId = newLine.raw.id if newLine

				if modified.isValid() and @canChangeTo modified
					$.extend @raw, modified.raw
					@place()

	renderDragHint: (dragInfo)->
		(@raw.renderDragHint ? @cfg().renderDragHint ? @constructor.renderDragHint).call @, dragInfo

	@renderDragHint: (dragInfo)->
		time =  @timeline.approxTime @timeline.getTime dragInfo.ui.position.left
		if time?
			@$dragHint.text moment.unix(time).format('DD.MM.YYYY HH:mm:ss')

	placeDragHint: (dragInfo)->
		(@raw.placeDragHint ? @cfg().placeDragHint ? @constructor.placeDragHint).call @, dragInfo

	@placeDragHint: (dragInfo)-> 
		@$dragHint.css
			left: dragInfo.event.pageX - dragInfo.parentOffset.left
			top: dragInfo.event.pageY - dragInfo.parentOffset.top

	makeResizeableLeft: ->
		$resizerLeft = Misc.addDom 'resizer-left', @$dom
		@$resizeHint = null
		modified = null
		originalDomOffset = null
		originalDomWidth = null

		$resizerLeft.draggable
			axis: 'x'
			helper: =>
				Misc.addDom('resize-helper-left').css
					width: $resizerLeft.css 'width'
					height: $resizerLeft.css 'height'
			start: (e, ui)=>
				@$resizeHint = Misc.addDom 'resize-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
				originalDomOffset = @timeline.getOffset @raw.from
				originalDomWidth = @timeline.getOffset(@raw.to - 1) - originalDomOffset
			stop: (e, ui)=>
				@$resizeHint.remove()
				modified = null
				originalDomOffset = null
				originalDomWidth = null
			drag: (e, ui)=>
				group = @getLine().getGroup()
				
				resizeInfo = 
					parentOffset: Misc.getScrollContainer(group.$dom).offset()
					event: e
					ui: ui
					left: originalDomOffset + (ui.position.left - ui.originalPosition.left)
					width: originalDomWidth - (ui.position.left - ui.originalPosition.left)
					side: 'left'

				$(ui.helper).css marginLeft: -(ui.position.left - ui.originalPosition.left)
				 
				@renderResizeHint resizeInfo
				@placeResizeHint resizeInfo
				
				modified.raw.from = @timeline.approxTime @timeline.getTime resizeInfo.left
				
				if modified.isValid() and @canChangeTo modified
					$.extend @raw, modified.raw
					@place()

	makeResizeableRight: ->
		$resizerRight = Misc.addDom 'resizer-right', @$dom
		@$resizeHint = null
		modified = null
		originalDomOffset = null
		originalDomWidth = null

		$resizerRight.draggable
			axis: 'x'
			helper: =>
				Misc.addDom('resize-helper-right').css
					width: $resizerRight.css 'width'
					height: $resizerRight.css 'height'
			start: (e, ui)=>
				@$resizeHint = Misc.addDom 'resize-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
				originalDomOffset = @timeline.getOffset @raw.from
				originalDomWidth = @timeline.getOffset(@raw.to - 1) - originalDomOffset
			stop: (e, ui)=>
				@$resizeHint.remove()
				modified = null
				originalDomOffset = null
				originalDomWidth = null
			drag: (e, ui)=>
				group = @getLine().getGroup()
				
				resizeInfo = 
					parentOffset: Misc.getScrollContainer(group.$dom).offset()
					event: e
					ui: ui
					left: originalDomOffset
					width: originalDomWidth + (ui.position.left - ui.originalPosition.left)
					side: 'right'
				 
				@renderResizeHint resizeInfo
				@placeResizeHint resizeInfo
				
				modified.raw.to = @timeline.approxTime @timeline.getTime(resizeInfo.left + resizeInfo.width), yes
				
				if modified.isValid() and @canChangeTo modified
					$.extend @raw, modified.raw
					@place()

	renderResizeHint: (resizeInfo)->
		(@raw.renderResizeHint ? @cfg().renderResizeHint ? @constructor.renderResizeHint).call @, resizeInfo

	@renderResizeHint: (resizeInfo)->
		offset = if resizeInfo.side is 'left'
			resizeInfo.left
		else 
			resizeInfo.left + resizeInfo.width

		time = @timeline.approxTime @timeline.getTime(offset), resizeInfo.side is 'right'
		if time?
			@$resizeHint.text moment.unix(time).format('DD.MM.YYYY HH:mm:ss')

	placeResizeHint: (resizeInfo)->
		(@raw.placeResizeHint ? @cfg().placeResizeHint ? @constructor.placeResizeHint).call @, resizeInfo

	@placeResizeHint: (resizeInfo)-> 
		@$resizeHint.css
			left: resizeInfo.event.pageX - resizeInfo.parentOffset.left
			top: resizeInfo.event.pageY - resizeInfo.parentOffset.top

	canChangeTo: (modified)->
		(@raw.canChangeTo ? @cfg().canChangeTo ? @constructor.canChangeTo).call @, modified

	@canChangeTo: (modified)->
		yes

	isValid: ->
		return no unless @raw.from < @raw.to

		rangeFrom = @timeline.getRangeByTime @raw.from
		return no unless rangeFrom?

		rangeTo = @timeline.getRangeByTime @raw.to - 1
		return no unless rangeTo?

		return no unless @canCrossRanges() or rangeFrom is rangeTo

		yes


window.Timeline = Timeline