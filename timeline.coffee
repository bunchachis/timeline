TL = {}

class TL.Resource
	construct: (@destroy)->
		@holdLevel = 0

	hold: ->
		@holdLevel++

	release: ->
		if --@holdLevel is 0
			@destroy()
		@destroy = undefined

class TL.Evented
	listenEvent: (name, fn)->
		@eventListeners ?= {}
		@eventListeners[name] ?= lastId: 0, funcs: []
		index = @eventListeners[name].lastId++
		@eventListeners[name].funcs[index] = fn
		new TL.Resource => @unlisten name, index

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
		$.extend event,
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

class TL.Sized
	getSize: (type, axis)->
		@['get' + type + axis]()

	calcSize: (axis)->
		verb = @['getRaw' + axis]()
		isString = $.type(verb) is 'string'
		if verb is 'auto'
			TL.Misc.sum(child.getSize 'Outer', axis for child in @getChildrenElements())
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

class TL.Timeline extends TL.Evented
	constructor: (container, config = {}, items = [])->
		@container = new TL.Element.Container $(container), @
		@config = $.extend yes, @getDefaultConfig(), config

		@root = @createElement 'Root'
		@sidebar = @createElement 'Sidebar'
		@ruler = @createElement 'Ruler'
		@corner = @createElement 'Corner'
		@field = @createElement 'Field'
		
		@ranges = []
		@rawAddRange range for range in @config.ranges
		@sortRanges()

		@groups = []
		@rawAddGroup group for group in @config.groups
		@sortGroups()

		@lines = []
		@rawAddLine line for line in @config.lines
		@sortLines()

		@dashRules = []
		@rawAddDashRule rule for rule in @config.dashRules
		@sortDashRules()

		@items = []
		@rawAddItem @createItem rawItem for rawItem in items

		@checkVerticalFitting()

		@root.build()

		@icm = new TL.InteractiveCreationMode @

	createElement: (type, data = {})->
		(@config.renderAtSidebar ? @constructor.createElement).call @, type, data

	@createElement: (type, data = {})->
		new TL.Element[type] @, data

	rawAddRange: (range)->
		for elseRange in @ranges
			if range.from < elseRange.raw.to and range.to > elseRange.raw.from 
				throw 'Can\'t add range overlapping existing one'

		@ranges.push @createElement 'Range', range

	sortRanges: ->
		@ranges = @ranges.sort (a, b)->
			a.raw.from - b.raw.from

	rawAddGroup: (group)->
		for elseGroup in @groups
			if elseGroup.raw.id is group.id
				throw 'Can\'t add group with same id as existing one has'

		@groups.push @createElement 'Group', group

	sortGroups: ->
		@groups = @groups.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	rawAddLine: (line)->
		for elseLine in @lines
			if elseLine.raw.id is line.id
				throw 'Can\'t add line with same id as existing one has'

		@lines.push @createElement 'Line', line

	sortLines: ->
		@lines = @lines.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	rawAddDashRule: (rule)->
		for elseRule in @dashRules
			if elseRule.id is rule.id
				throw 'Can\'t add dash rule with same id as existing one has'

		@dashRules.push rule

	sortDashRules: ->
		@dashRules = @dashRules.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	createItem: (raw)->
		item = @createElement 'Item', raw

	rawAddItem: (item)->
		unless item.isValid()
			throw 'Can\'t add item due to its invalidity'

		@items.push item 

	addItem: (item)->
		@rawAddItem item
		item.build()

	getDefaultConfig: ->
		field:
			render: null
			place: null
		corner:
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
			extraOffsetBefore: null
			extraOffsetAfter: null
			render: null
			place: null
			renderAtRuler: null
			placeAtRuler: null
		group:
			height: 'auto'
			extraOffsetBefore: null
			extraOffsetAfter: null
			render: null
			place: null
		line:
			height: 50
			extraOffsetBefore: null
			extraOffsetAfter: null
			render: null
			place: null
			renderAtSidebar: null
			placeAtSidebar: null
		item:
			isDraggable: yes
			canCrossRanges: yes
			render: null
			place: null
			isValid: null
		dash:
			render: null
			place: null
		scale: 1
		timezone: 'UTC'
		snapResolution: 1
		height: '100%'
		createElement: null
		dashRules: []
		ranges: []
		groups: []
		lines: []

	calcDashes: ->
		dashes = []
		for dashRule in @dashRules 
			step = dashRule.step ? Infinity
			offset = dashRule.offset ? 0
			for range in @ranges
				if step is Infinity
					time = offset
				else 
					time = Math.floor(range.raw.from / step) * step + offset

				while time < range.raw.to
					dashes.push {time, rule: dashRule} if time >= range.raw.from
					time += step
		
		map = {}
		map[dash.time] = dash for dash in dashes when !map[dash.time]?

		dashes = []
		dashes.push @createElement 'Dash', dash for time, dash of map
		dashes

	getGroupById: (groupId)->
		if groupId?
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

class TL.InteractiveCreationMode
	constructor: (@timeline)->
		@isActive = no
		@build()

	build: ->
		@$helpers = []
		@$dashes = []
		for group in @timeline.groups
			$dash = TL.Misc.addDom 'icm-dash', group.$dom 
			@$dashes.push $dash
			$helper = TL.Misc.addDom 'icm-helper', group.$dom
			@$helpers.push $helper

		@$hint = TL.Misc.addDom 'icm-hint'

		@placeDashes()
		@placeHelpers()

	activate: (@itemTemplate = {}, groupId)->
		@isActive = yes
		@group = @timeline.getGroupById groupId
		@activateState 'SetBeginning'

	deactivate: ->
		@isActive = no
		@itemTemplate = null
		@from = null
		@to = null
		@line = null
		@group = null
		@deactivateState @stateName

	activateState: (stateName)->
		@deactivateState @stateName
		@stateName = stateName
		@['activateState' + @stateName]()

	deactivateState: (stateName)->
		@['deactivateState' + stateName]() if stateName?
		@stateName = null

	activateStateSetBeginning: ->
		fieldOffset = TL.Misc.getScrollContainer(@timeline.field.$dom).offset()
		@moveHandler = (e)=>
			group = $(e.target).parents('.tl-group').data('timeline-host-object')
			mouseInfo = event: e
			if group?
				groupOffset = TL.Misc.getScrollContainer(group.$dom).offset()
				mouseInfo.group = group
				mouseInfo.parentOffset = groupOffset
				@line = @timeline.getLineByVerticalOffset(group, e.pageY - groupOffset.top)
				@from = @timeline.approxTime @timeline.getTime(e.pageX - groupOffset.left)
			else
				@from = null

			@placeDashes()
			@placeHelpers()
			@placeHint mouseInfo
			@renderHint mouseInfo
		@timeline.field.$dom.on 'mousemove', @moveHandler

		@leaveHandler = (e)=>
			@from = null

			@placeDashes()
			@placeHelpers()
			@placeHint {}
			@renderHint {}
		@timeline.field.$dom.on 'mouseleave', @leaveHandler

		@clickHandler = (e)=>
			if @from?
				@activateState 'SetEnding'
		@timeline.field.$dom.on 'click', @clickHandler	

	deactivateStateSetBeginning: ->
		@placeDashes()
		@placeHelpers()
		@placeHint {}
		@renderHint {}
		@timeline.field.$dom.off 'mousemove', @moveHandler
		@moveHandler = null
		@timeline.field.$dom.off 'mouseleave', @leaveHandler
		@leaveHandler = null
		@timeline.field.$dom.off 'click', @clickHandler
		@clickHandler = null

	activateStateSetEnding: ->
		fieldOffset = TL.Misc.getScrollContainer(@timeline.field.$dom).offset()
		@moveHandler = (e)=>
			group = $(e.target).parents('.tl-group').data('timeline-host-object')
			mouseInfo = event: e
			if group?
				groupOffset = TL.Misc.getScrollContainer(group.$dom).offset()
				mouseInfo.group = group
				mouseInfo.parentOffset = groupOffset
				mouseTime = @timeline.getTime(e.pageX - groupOffset.left)
				@to = @timeline.approxTime mouseTime, yes
			else
				@to = null

			@placeDashes()
			@placeHelpers()
			@placeHint mouseInfo
			@renderHint mouseInfo
		@timeline.field.$dom.on 'mousemove', @moveHandler

		@leaveHandler = (e)=>
			@to = null

			@placeDashes()
			@placeHelpers()
			@placeHint {}
			@renderHint {}
		@timeline.field.$dom.on 'mouseleave', @leaveHandler

		@clickHandler = (e)=>
			if @to?
				item = @timeline.createItem $.extend {}, @itemTemplate, 
					from: @from
					to: @to
					lineId: @line.raw.id

				if item.isValid()
					if @timeline.fireEvent 'item:create', {item}
						@timeline.addItem item
						@deactivate()
		@timeline.field.$dom.on 'click', @clickHandler	

	deactivateStateSetEnding: ->
		@placeDashes()
		@placeHelpers()
		@placeHint {}
		@renderHint {}
		@timeline.field.$dom.off 'mousemove', @moveHandler
		@moveHandler = null
		@timeline.field.$dom.off 'mouseleave', @leaveHandler
		@leaveHandler = null
		@timeline.field.$dom.off 'click', @clickHandler
		@clickHandler = null

	placeDashes: ->
		@placeDash $dash for $dash in @$dashes

	placeDash: ($dash)->
		offset = @timeline.getOffset switch @stateName
			when 'SetBeginning' then @from
			when 'SetEnding' then @to - 1

		if @isActive and offset?
			$dash.css
				display: 'block'
				left: offset
		else
			$dash.css
				display: 'none'

	placeHelpers: ->
		@placeHelper $helper for $helper in @$helpers

	placeHelper: ($helper)->
		group = $helper.parents('.tl-group').data 'timeline-host-object'
		
		if group is @line?.getGroup()
			switch @stateName
				when 'SetBeginning'
					offset = @timeline.getOffset @from
					width = ''
				when 'SetEnding'
					offset = @timeline.getOffset @from
					width = if @to? then @timeline.getOffset(@to - 1) - offset else null
		
		if @isActive and @line? and offset? and width?
			$helper.css
				display: 'block'
				left: offset
				width: width
				top: @line.getVerticalOffset() + @line.getInternalVerticalOffset()
				height: @line.getInnerHeight()
		else
			$helper.css
				display: 'none'

	renderHint: (mouseInfo)->
		(@timeline.config.icm?.renderHint ? @constructor.renderHint).call @, mouseInfo

	@renderHint: (mouseInfo)->
		if @isActive and mouseInfo.group?
			offset = mouseInfo.event.pageX - mouseInfo.parentOffset.left
			time = @timeline.approxTime @timeline.getTime(offset), @stateName is 'SetEnding'
			if time?
				@$hint.text moment.unix(time).tz(@timeline.config.timezone).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')
		else 
			@$hint.empty()

	placeHint: (mouseInfo)->
		(@timeline.config.icm?.placeHint ? @constructor.placeHint).call @, mouseInfo

	@placeHint: (mouseInfo)->
		if @isActive and mouseInfo.group?
			@$hint.appendTo TL.Misc.getScrollContainer mouseInfo.group.$dom
			@$hint.css
				left: mouseInfo.event.pageX - mouseInfo.parentOffset.left
				top: mouseInfo.event.pageY - mouseInfo.parentOffset.top
		else
			@$hint.detach()

class TL.Misc
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

class TL.Element extends TL.Sized
	constructor: (@timeline, @raw = {})->
		@className = @getClassName()
		@init()

	getClassName: ->
		''

	init: ->

	cfg: ->
		@timeline.config[@className] ? {}

	getRawHeight: ->
		@lookupProperty 'height', 'auto'

	getExtraOffsetBefore: ->
		@lookupProperty 'extraOffsetBefore', 0

	getExtraOffsetAfter: ->
		@lookupProperty 'extraOffsetAfter', 0

	lookupProperty: (name, fallbackValue)->
		@raw[name] ? @cfg()[name] ? @constructor[name] ? fallbackValue

class TL.Element.Container extends TL.Sized
	constructor: (@$dom, @timeline)->

	getRawHeight: ->
		0

	getInnerHeight: ->
		@$dom.innerHeight()

	getChildrenElements: ->
		[@timeline]

class TL.Element.Root extends TL.Element
	getClassName: ->
		'root'

	build: ->
		@$dom = TL.Misc.addDom 'root', @timeline.container.$dom
		@render()
		@place()

		@timeline.sidebar.build()
		@timeline.ruler.build()
		@timeline.corner.build()
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

class TL.Element.Sidebar extends TL.Element
	getClassName: ->
		'sidebar'

	isVisible: ->
		@lookupProperty 'isVisible', yes

	getOuterWidth: ->
		if @isVisible()
			@getInnerWidth()
		else
			0

	getInnerWidth: ->
		if @isVisible()
			@lookupProperty 'width', 100
		else
			0

	build: ->
		@$dom = TL.Misc.addDom 'sidebar', @timeline.root.$dom
		@render()
		@place()

		@buildGroups()

	render: ->
		@lookupProperty('render').call @

	@render: ->

	place: ->
		@lookupProperty('place').call @

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

class TL.Element.Ruler extends TL.Element
	getClassName: ->
		'ruler'

	isVisible: ->
		@lookupProperty 'isVisible', yes

	getRawHeight: ->
		if @isVisible() then super() else 0

	getExtraOffsetBefore: ->
		if @isVisible() then super() else 0

	getExtraOffsetAfter: ->
		if @isVisible() then super() else 0

	getParentElement: ->
		@timeline.root

	build: ->
		@$dom = TL.Misc.addDom 'ruler', @timeline.root.$dom
		TL.Misc.scrollize @$dom, 'x', [{axis: 'x', getTarget: => group.$dom for group in @timeline.groups}]
		@render()
		@place()
		
		@buildRanges()
		@buildDashes()

	render: ->
		@lookupProperty('render').call @

	@render: ->

	place: ->
		@lookupProperty('place').call @

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

		TL.Misc.setInnerSize @$dom, 
			x: TL.Misc.sum(range.getOuterWidth() for range in @timeline.ranges)
			y: @timeline.ruler.getInnerHeight()

	buildRanges: ->
		range.buildAtRuler() for range in @timeline.ranges

	buildDashes: ->
		dash.buildAtRuler() for dash in @timeline.calcDashes()

class TL.Element.Corner extends TL.Element
	getClassName: ->
		'corner'

	build: ->
		@$dom = TL.Misc.addDom 'corner', @timeline.root.$dom
		@render()
		@place()

	render: ->
		@lookupProperty('render').call @

	@render: ->

	place: ->
		@lookupProperty('place').call @

	@place: ->
		@$dom.css if @timeline.config.ruler.position is 'top'
			top: 0
			bottom: ''
		else
			top: ''
			bottom: 0

		@$dom.css if @timeline.config.sidebar.position is 'left'
			left: 0
			right: ''
		else 
			left: ''
			right: 0
			
		@$dom.css
			width: @timeline.sidebar.getOuterWidth()
			height: @timeline.ruler.getOuterHeight()

class TL.Element.Field extends TL.Element
	getClassName: ->
		'field'

	build: ->
		@$dom = TL.Misc.addDom 'field', @timeline.root.$dom
		@render()
		@place()

		@buildGroups()

	render: ->
		@lookupProperty('render').call @

	@render: ->

	place: ->
		@lookupProperty('place').call @

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

class TL.Element.Group extends TL.Element
	getClassName: ->
		'group'

	getLines: ->
		line for line in @timeline.lines when line.raw.groupId is @raw.id

	getVerticalOffset: ->
		x = TL.Misc.sum(
			for elseGroup in @timeline.groups
				break if elseGroup.raw.id is @raw.id
				elseGroup.getOuterHeight() 
		)

	getParentElement: ->
		@timeline.root

	getChildrenElements: ->
		@getLines()

	build: ->
		@$dom = TL.Misc.addDom 'group', @timeline.field.$dom
		@$dom.data 'timeline-host-object', @
		TL.Misc.scrollize @$dom, 'xy', [
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
		@lookupProperty('render').call @

	@render: ->

	place: ->
		@lookupProperty('place').call @

	@place: ->
		@$dom.css
			top : @getVerticalOffset()
			height: @getInnerHeight()

		TL.Misc.setInnerSize @$dom, 
			x: TL.Misc.sum(range.getOuterWidth() for range in @timeline.ranges)
			y: TL.Misc.sum(line.getOuterHeight() for line in @getLines())

	buildLines: ->
		line.build() for line in @getLines()

	buildRanges: ->
		range.build @ for range in @timeline.ranges

	buildDashes: ->
		dash.build @ for dash in @timeline.calcDashes()

	buildItems: ->
		item.build() for item in @timeline.items when item.getLine().raw.groupId is @raw.id

	buildAtSidebar: ->
		@$sidebarDom = TL.Misc.addDom 'group', @timeline.sidebar.$dom
		TL.Misc.scrollize @$sidebarDom, 'y', [{axis: 'y', getTarget: => @$dom}]
		@renderAtSidebar()
		@placeAtSidebar()

		@buildLinesAtSidebar()

	renderAtSidebar: ->
		@lookupProperty('renderAtSidebar').call @

	@renderAtSidebar: ->

	placeAtSidebar: ->
		@lookupProperty('placeAtSidebar').call @

	@placeAtSidebar: ->
		@$sidebarDom.css
			top : @getVerticalOffset()
			height: @getInnerHeight()

		TL.Misc.setInnerSize @$sidebarDom,
			x: @timeline.sidebar.getInnerWidth()
			y: TL.Misc.sum(line.getOuterHeight() for line in @getLines())

	buildLinesAtSidebar: ->
		line.buildAtSidebar() for line in @getLines()

class TL.Element.Range extends TL.Element
	getClassName: ->
		'range'

	init: ->
		@$doms = []

	getOffset: ->
		TL.Misc.sum(
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

	getTimeByOffset: (offset)->
		@getTimeByInternalOffset(offset - @getOffset() - @getExtraOffsetBefore())

	getTimeByInternalOffset: (internalOffset)->
		@raw.from + internalOffset * @timeline.config.scale

	build: (group)->
		$dom = TL.Misc.addDom 'range', group.$dom
		@$doms.push $dom
		@render $dom
		@place $dom

	render: ($dom)->
		@lookupProperty('render').call @, $dom

	@render: ($dom)->

	place: ($dom)->
		@lookupProperty('place').call @, $dom

	@place: ($dom)->
		$dom.css
			left: @getOffset()
			width: @getInnerWidth()

	buildAtRuler: ->
		@$rulerDom = TL.Misc.addDom 'range', @timeline.ruler.$dom
		@renderAtRuler()
		@placeAtRuler()

	renderAtRuler: ->
		@lookupProperty('renderAtRuler').call @

	@renderAtRuler: ->
		from = moment.unix(@raw.from).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')
		to = moment.unix(@raw.to).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')
		@$rulerDom.empty().append TL.Misc.addDom('heading').text "#{from} — #{to}"

	placeAtRuler: ->
		@lookupProperty('placeAtRuler').call @

	@placeAtRuler: ->
		@$rulerDom.css
			left: @getOffset()
			width: @getInnerWidth()

class TL.Element.Dash extends TL.Element
	getClassName: ->
		'dash'

	init: ->
		@$doms = []

	build: (group)->
		$dom = TL.Misc.addDom 'dash', group.$dom
		$dom.addClass "id-#{@raw.rule.id}"
		@$doms.push $dom
		@render $dom
		@place $dom

	render: ($dom)->
		@lookupProperty('render').call @, $dom

	@render: ($dom)->
		$dom.empty()

	place: ($dom)->
		@lookupProperty('place').call @, $dom

	@place: ($dom)->
		offset = @timeline.getOffset @raw.time
		if offset?
			$dom.css left: offset

	buildAtRuler: (dash)->
		@$rulerDom = TL.Misc.addDom 'dash', @timeline.ruler.$dom
		@$rulerDom.addClass "id-#{@raw.rule.id}"
		@renderAtRuler()
		@placeAtRuler()

	renderAtRuler: ->
		@lookupProperty('renderAtRuler').call @

	@renderAtRuler: ->
		@$rulerDom.empty().append TL.Misc.addDom('text').text moment.unix(@raw.time).tz(@timeline.config.timezone).format('HH:mm')

	placeAtRuler: ->
		@lookupProperty('placeAtRuler').call @

	@placeAtRuler: ->
		offset = @timeline.getOffset @raw.time
		if offset?
			@$rulerDom.css left: offset

class TL.Element.Line extends TL.Element
	getClassName: ->
		'line'

	getVerticalOffset: ->
		TL.Misc.sum(
			for elseLine in @timeline.lines when elseLine.raw.groupId is @raw.groupId
				break if elseLine.raw.id is @raw.id
				elseLine.getOuterHeight() 
		)

	getInternalVerticalOffset: ->
		@getExtraOffsetBefore()	

	getParentElement: ->
		@getGroup()

	getRawHeight: ->
		@lookupProperty 'height', 0

	getInnerHeight: ->
		@calcSize 'Height'

	getOuterHeight: ->
		@getInnerHeight() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getGroup: ->
		@timeline.getGroupById @raw.groupId

	build: ->
		@$dom = TL.Misc.addDom 'line', @getGroup().$dom
		@render()
		@place()

	render: ->
		@lookupProperty('render').call @

	@render: ->
		@$dom.empty()

	place: ->
		@lookupProperty('place').call @

	@place: ->
		@$dom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

	buildAtSidebar: ->
		@$sidebarDom = TL.Misc.addDom 'line', @getGroup().$sidebarDom
		@renderAtSidebar()
		@placeAtSidebar()

	renderAtSidebar: ->
		@lookupProperty('renderAtSidebar').call @

	@renderAtSidebar: ->
		@$sidebarDom.empty().append TL.Misc.addDom('heading').text @raw.id

	placeAtSidebar: ->
		@lookupProperty('placeAtSidebar').call @

	@placeAtSidebar: ->
		@$sidebarDom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

class TL.Element.Item extends TL.Element
	getClassName: ->
		'item'

	getLine: ->
		@timeline.getLineById @raw.lineId

	getDuration: ->
		@raw.to - @raw.from

	isDraggable: ->
		@lookupProperty 'isDraggable', yes

	canCrossRanges: ->
		@lookupProperty 'canCrossRanges', yes

	build: ->
		@$dom = TL.Misc.addDom 'item', @getLine().getGroup().$dom
		@render()
		@place()
		@makeDraggable()
		@makeResizeableLeft()
		@makeResizeableRight()

	render: ->
		@lookupProperty('render').call @

	@render: ->
		@$dom.empty().append TL.Misc.addDom('text').text @raw.text

	place: ->
		@lookupProperty('place').call @

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
				TL.Misc.addDom('drag-helper').css
					width: @$dom.css 'width'
					height: @$dom.css 'height'
			start: (e, ui)=>
				@$dragHint = TL.Misc.addDom 'drag-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
				@timeline.fireEvent 'item:drag:start', item: @
			stop: (e, ui)=>
				@$dragHint.remove()
				modified = null
				@timeline.fireEvent 'item:drag:stop', item: @
			drag: (e, ui)=>
				group = @getLine().getGroup()
				dragInfo = 
					parentOffset: TL.Misc.getScrollContainer(group.$dom).offset()
					event: e
					ui: ui
				
				@renderDragHint dragInfo
				@placeDragHint dragInfo
				

				duration = @getDuration()
				modified.raw.from = @timeline.approxTime @timeline.getTime dragInfo.ui.position.left
				modified.raw.to = modified.raw.from + duration
				newLine = @timeline.getLineByVerticalOffset group, dragInfo.event.pageY - dragInfo.parentOffset.top
				modified.raw.lineId = newLine.raw.id if newLine

				if modified.isValid()
					if @timeline.fireEvent('item:drag', item: modified, originalItem: @) and
					@timeline.fireEvent('item:modify', item: modified, originalItem: @)
						$.extend @raw, modified.raw
						@place()

	renderDragHint: (dragInfo)->
		@lookupProperty('renderDragHint').call @, dragInfo

	@renderDragHint: (dragInfo)->
		time =  @timeline.approxTime @timeline.getTime dragInfo.ui.position.left
		if time?
			@$dragHint.text moment.unix(time).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')

	placeDragHint: (dragInfo)->
		@lookupProperty('placeDragHint').call @, dragInfo

	@placeDragHint: (dragInfo)-> 
		@$dragHint.css
			left: dragInfo.event.pageX - dragInfo.parentOffset.left
			top: dragInfo.event.pageY - dragInfo.parentOffset.top

	makeResizeableLeft: ->
		$resizerLeft = TL.Misc.addDom 'resizer-left', @$dom
		@$resizeHint = null
		modified = null
		originalDomOffset = null
		originalDomWidth = null

		$resizerLeft.draggable
			axis: 'x'
			helper: =>
				TL.Misc.addDom('resize-helper-left').css
					width: $resizerLeft.css 'width'
					height: $resizerLeft.css 'height'
			start: (e, ui)=>
				@$resizeHint = TL.Misc.addDom 'resize-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
				originalDomOffset = @timeline.getOffset @raw.from
				originalDomWidth = @timeline.getOffset(@raw.to - 1) - originalDomOffset
				@timeline.fireEvent 'item:resize:start', item: @
			stop: (e, ui)=>
				@$resizeHint.remove()
				modified = null
				originalDomOffset = null
				originalDomWidth = null
				@timeline.fireEvent 'item:resize:stop', item: @
			drag: (e, ui)=>
				group = @getLine().getGroup()
				
				resizeInfo = 
					parentOffset: TL.Misc.getScrollContainer(group.$dom).offset()
					event: e
					ui: ui
					left: originalDomOffset + (ui.position.left - ui.originalPosition.left)
					width: originalDomWidth - (ui.position.left - ui.originalPosition.left)
					side: 'left'

				$(ui.helper).css marginLeft: -(ui.position.left - ui.originalPosition.left)
				 
				@renderResizeHint resizeInfo
				@placeResizeHint resizeInfo
				
				modified.raw.from = @timeline.approxTime @timeline.getTime resizeInfo.left
				
				if modified.isValid()
					if @timeline.fireEvent('item:resize', item: modified, originalItem: @) and
					@timeline.fireEvent('item:modify', item: modified, originalItem: @)
						$.extend @raw, modified.raw
						@place()

	makeResizeableRight: ->
		$resizerRight = TL.Misc.addDom 'resizer-right', @$dom
		@$resizeHint = null
		modified = null
		originalDomOffset = null
		originalDomWidth = null

		$resizerRight.draggable
			axis: 'x'
			helper: =>
				TL.Misc.addDom('resize-helper-right').css
					width: $resizerRight.css 'width'
					height: $resizerRight.css 'height'
			start: (e, ui)=>
				@$resizeHint = TL.Misc.addDom 'resize-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
				originalDomOffset = @timeline.getOffset @raw.from
				originalDomWidth = @timeline.getOffset(@raw.to - 1) - originalDomOffset
				@timeline.fireEvent 'item:resize:start', item: @
			stop: (e, ui)=>
				@$resizeHint.remove()
				modified = null
				originalDomOffset = null
				originalDomWidth = null
				@timeline.fireEvent 'item:resize:stop', item: @
			drag: (e, ui)=>
				group = @getLine().getGroup()
				
				resizeInfo = 
					parentOffset: TL.Misc.getScrollContainer(group.$dom).offset()
					event: e
					ui: ui
					left: originalDomOffset
					width: originalDomWidth + (ui.position.left - ui.originalPosition.left)
					side: 'right'
				 
				@renderResizeHint resizeInfo
				@placeResizeHint resizeInfo
				
				modified.raw.to = @timeline.approxTime @timeline.getTime(resizeInfo.left + resizeInfo.width), yes
				
				if modified.isValid()
					if @timeline.fireEvent('item:resize', item: modified, originalItem: @) and
					@timeline.fireEvent('item:modify', item: modified, originalItem: @)
						$.extend @raw, modified.raw
						@place()


	renderResizeHint: (resizeInfo)->
		@lookupProperty('renderResizeHint').call @, resizeInfo

	@renderResizeHint: (resizeInfo)->
		offset = if resizeInfo.side is 'left'
			resizeInfo.left
		else 
			resizeInfo.left + resizeInfo.width

		time = @timeline.approxTime @timeline.getTime(offset), resizeInfo.side is 'right'
		if time?
			@$resizeHint.text moment.unix(time).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')

	placeResizeHint: (resizeInfo)->
		@lookupProperty('placeResizeHint').call @, resizeInfo

	@placeResizeHint: (resizeInfo)-> 
		@$resizeHint.css
			left: resizeInfo.event.pageX - resizeInfo.parentOffset.left
			top: resizeInfo.event.pageY - resizeInfo.parentOffset.top

	isValid: ->
		@lookupProperty('isValid').call @

	@isValid: ->
		return no unless @raw.from < @raw.to

		return no if @raw.minDuration? and @raw.to - @raw.from < @raw.minDuration

		rangeFrom = @timeline.getRangeByTime @raw.from
		return no unless rangeFrom?

		rangeTo = @timeline.getRangeByTime @raw.to - 1
		return no unless rangeTo?

		return no unless @canCrossRanges() or rangeFrom is rangeTo

		yes

	remove: ->
		@destroy()
		@timeline.items = @timeline.items.filter (item)=> @ isnt item

	destroy: ->
		if @$dom?
			@$dom?.remove()
			@$dom = null
		if @$dragHint?
			@$dragHint?.remove()
			@$dragHint = null
		if @$resizeHint?
			@$resizeHint?.remove()
			@$resizeHint = null


window.TL = TL