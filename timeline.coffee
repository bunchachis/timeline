window.TL = TL = {}

TL.mixOf = (mixins...) ->
	class Mixed
		@mixinInitters = []
		@mixinDeinitters = []

		constructor: ->
			@initMixins()

		destructor: ->
			@deinitMixins()

		initMixins: ->
			initter.call @ for initter in @constructor.mixinInitters
			null

		deinitMixins: ->
			deinitter.call @ for deinitter in @constructor.mixinDeinitters
			null

		for Mixin in mixins by -1
			for name, method of Mixin::
				switch name
					when 'init' then Mixed.mixinInitters.push method
					when 'deinit' then Mixed.mixinDeinitters.push method
					else Mixed::[name] = method
	Mixed

class TL.Resource
	construct: (@destroy)->
		@holdLevel = 0

	hold: ->
		@holdLevel++

	release: ->
		if --@holdLevel is 0
			@destroy()
		@destroy = undefined

class TL.ResourceHolder
	holdResource: (resource)->
		@heldResources ?= []
		resource.hold()
		@heldResources.push resource

	releaseResources: ->
		if @heldResources?
			resource.release() for resource in @heldResources
			@heldResources = []

class TL.EventEmitter
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

class TL.Timeline extends TL.EventEmitter
	constructor: (container, config = {}, items = [])->
		@container = new TL.Element.Container $(container), @
		@config = $.extend yes, @getDefaultConfig(), config

		@root = @createElement 'Root'
		@sidebar = @createElement 'Sidebar'
		@ruler = @createElement 'Ruler'
		@corner = @createElement 'Corner'
		@field = @createElement 'Field'
		
		@groups = []
		@ranges = []
		@lines = []
		@dashRules = []
		@dashes = []
		@items = []

		@rawAddGroup group for group in @config.groups
		@sortGroups()

		@rawAddRange range for range in @config.ranges
		@sortRanges()

		@rawAddLine line for line in @config.lines
		@sortLines()

		@rawAddDashRule rule for rule in @config.dashRules
		@sortDashRules()

		@rawAddItem @createItem rawItem for rawItem in items

		@checkVerticalFitting()

		@now = @createElement 'Now'

		@icm = new TL.InteractiveCreationMode @

		@render()

	render: ->
		if @fireEvent 'render'
			@root.render()
			@sidebar.render()
			@ruler.render()
			@corner.render()
			@field.render()
			group.render() for group in @groups
			range.render() for range in @ranges
			line.render() for line in @lines
			dash.render() for dash in @dashes
			item.render() for item in @items
			@now.render()
			@icm.render()

	warn: (message)->
		if @config.isStrict
			throw new Error message
		else 
			console?.error? message 

	createElement: (type, data = {})->
		(@config.fillAtSidebar ? @constructor.createElement).call @, type, data

	@createElement: (type, data = {})->
		new TL.Element[type] @, data

	rawAddRange: (range)->
		for elseRange in @ranges
			if range.from < elseRange.raw.to and range.to > elseRange.raw.from 
				@warn 'Can\'t add range overlapping existing one'
				return

		@ranges.push @createElement 'Range', range

	sortRanges: ->
		@ranges = @ranges.sort (a, b)->
			a.raw.from - b.raw.from

	rawAddGroup: (group)->
		for elseGroup in @groups
			if elseGroup.raw.id is group.id
				@warn 'Can\'t add group with same id as existing one has'
				return

		@groups.push @createElement 'Group', group

	sortGroups: ->
		@groups = @groups.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	rawAddLine: (line)->
		for elseLine in @lines
			if elseLine.raw.id is line.id
				@warn 'Can\'t add line with same id as existing one has'
				return

		@lines.push @createElement 'Line', line

	sortLines: ->
		@lines = @lines.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	rawAddDashRule: (rule)->
		for elseRule in @dashRules
			if elseRule.raw.id is rule.id
				@warn 'Can\'t add dash rule with same id as existing one has'
				return

		@dashRules.push @createElement 'DashRule', rule

	sortDashRules: ->
		@dashRules = @dashRules.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	createItem: (raw)->
		item = @createElement 'Item', raw

	rawAddItem: (item)->
		unless item.isValid()
			@warn 'Can\'t add item due to its invalidity'
			return

		@items.push item 

	addItem: (item)->
		if @fireEvent 'item:create', {item}
			@rawAddItem item
			item.render()
			yes
		else
			no

	getDefaultConfig: ->
		field:
			fill: null
			place: null
		corner:
			fill: null
			place: null
		ruler:
			isVisible: yes
			position: 'top'
			height: 50
			fill: null
			place: null
		sidebar:
			isVisible: yes
			position: 'left'
			width: 100
			fill: null
			place: null
		range:
			extraOffsetBefore: null
			extraOffsetAfter: null
			fill: null
			place: null
			fillAtRuler: null
			placeAtRuler: null
		group:
			height: 'auto'
			extraOffsetBefore: null
			extraOffsetAfter: null
			fill: null
			place: null
		line:
			height: 50
			extraOffsetBefore: null
			extraOffsetAfter: null
			fill: null
			place: null
			fillAtSidebar: null
			placeAtSidebar: null
		item:
			isDraggable: yes
			isResizable: yes
			canCrossRanges: yes
			fill: null
			place: null
			isValid: null
		dash:
			fill: null
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
		isStrict: no
		scrollPointPosition: .1 # float [0 to 1]

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

	getDashRuleById: (ruleId)->
		for rule in @dashRules
			if rule.raw.id is ruleId
				return rule

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

	scrollToTime: (time)->
		time ?= @getCurrentTime()
		
		offset = @getOffset time
		console.log "Preoffset: #{offset}"
		unless offset?
			for range in @ranges
				rangeBeforeTime = range if range.raw.to <= time
			offset = if rangeBeforeTime?
				rangeBeforeTime.getOffset() + rangeBeforeTime.getOuterWidth() - 1
			else
				0
		console.log rangeBeforeTime
		console.log "Postoffset: #{offset}"

		viewWidth = @field.getView().$dom.width()
		#fullWidth = TL.Misc.sum(range.getOuterWidth() for range in @ranges)

		offset = offset - viewWidth * @config.scrollPointPosition
		offset = 'left' if offset < 0
		console.log "Final offset: #{offset}"
		@ruler.getView().$dom.mCustomScrollbar 'scrollTo', x: offset

	getCurrentTime: ->
		nowString = moment().format('DD.MM.YYYY HH:mm:ss')
		moment.tz(nowString, 'DD.MM.YYYY HH:mm:ss', @config.timezone).unix()

class TL.InteractiveCreationMode
	constructor: (@timeline)->
		@isActive = no
		@escHandler = (e)=>
			@deactivate() if e.which is 27
		@build()

	build: ->
		@$helpers = []
		@$dashes = []
		for group in @timeline.groups
			$dash = TL.Misc.addDom 'icm-dash', group.getView().$dom 
			@$dashes.push $dash
			$helper = TL.Misc.addDom 'icm-helper', group.getView().$dom
			@$helpers.push $helper

		@$hint = TL.Misc.addDom 'icm-hint'

		@$indicator = TL.Misc.addDom 'icm-indicator'
		@$indicator.append $('<p />').text 'Создание элемента'
		@$indicator.append $('<button />').text('отменить').click => @deactivate()

	render: ->
		@placeDashes()
		@placeHelpers()

	activate: (@itemTemplate = {}, @restrictGroupsIds)->
		@isActive = yes
		@$oldCornerContent = @timeline.corner.getView().$dom.children()
		@timeline.corner.getView().$dom.empty().append @$indicator
		$(window).on 'keydown', @escHandler
		@activateState 'SetBeginning'

	deactivate: ->
		@isActive = no
		@$indicator.detach()
		@timeline.corner.getView().$dom.empty().append @$oldCornerContent
		@$oldCornerContent = null
		$(window).off 'keydown', @escHandler
		@itemTemplate = null
		@from = null
		@to = null
		@line = null
		@restrictGroupsIds = null
		@deactivateState @stateName

	activateState: (stateName)->
		@deactivateState @stateName
		@stateName = stateName
		@['activateState' + @stateName]()

	deactivateState: (stateName)->
		@['deactivateState' + stateName]() if stateName?
		@stateName = null

	activateStateSetBeginning: ->
		fieldOffset = TL.Misc.getScrollContainer(@timeline.field.getView().$dom).offset()
		@moveHandler = (e)=>
			group = $(e.target).parents('.tl-group').data('timeline-host-object')
			mouseInfo = event: e
			if group? and (!@restrictGroupsIds? or group.raw.id in @restrictGroupsIds)
				groupOffset = TL.Misc.getScrollContainer(group.getView().$dom).offset()
				mouseInfo.group = group
				mouseInfo.parentOffset = groupOffset
				@line = @timeline.getLineByVerticalOffset(group, e.pageY - groupOffset.top)
				@from = @timeline.approxTime @timeline.getTime(e.pageX - groupOffset.left)
			else
				@line = null
				@from = null

			@render()
			@renderHint mouseInfo
		@timeline.field.getView().$dom.on 'mousemove', @moveHandler

		@leaveHandler = (e)=>
			@line = null
			@from = null

			@render()
			@renderHint {}
		@timeline.field.getView().$dom.on 'mouseleave', @leaveHandler

		@clickHandler = (e)=>
			if @from?
				@activateState 'SetEnding'
		@timeline.field.getView().$dom.on 'click', @clickHandler	

	deactivateStateSetBeginning: ->
		@render()
		@renderHint {}
		@timeline.field.getView().$dom.off 'mousemove', @moveHandler
		@moveHandler = null
		@timeline.field.getView().$dom.off 'mouseleave', @leaveHandler
		@leaveHandler = null
		@timeline.field.getView().$dom.off 'click', @clickHandler
		@clickHandler = null

	activateStateSetEnding: ->
		fieldOffset = TL.Misc.getScrollContainer(@timeline.field.getView().$dom).offset()
		@moveHandler = (e)=>
			group = $(e.target).parents('.tl-group').data('timeline-host-object')
			mouseInfo = event: e
			if group?
				groupOffset = TL.Misc.getScrollContainer(group.getView().$dom).offset()
				mouseInfo.group = group
				mouseInfo.parentOffset = groupOffset
				mouseTime = @timeline.getTime(e.pageX - groupOffset.left)
				@to = @timeline.approxTime mouseTime, yes
			else
				@to = null

			@render()
			@renderHint mouseInfo
		@timeline.field.getView().$dom.on 'mousemove', @moveHandler

		@leaveHandler = (e)=>
			@to = null

			@render()
			@renderHint {}
		@timeline.field.getView().$dom.on 'mouseleave', @leaveHandler

		@clickHandler = (e)=>
			if @to?
				item = @timeline.createItem $.extend @itemTemplate, 
					from: @from
					to: @to
					lineId: @line.raw.id

				if item.isValid()
					if @timeline.addItem item
						@deactivate()
		@timeline.field.getView().$dom.on 'click', @clickHandler	

	deactivateStateSetEnding: ->
		@render()
		@renderHint {}
		@timeline.field.getView().$dom.off 'mousemove', @moveHandler
		@moveHandler = null
		@timeline.field.getView().$dom.off 'mouseleave', @leaveHandler
		@leaveHandler = null
		@timeline.field.getView().$dom.off 'click', @clickHandler
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
		@fillHint mouseInfo
		@placeHint mouseInfo

	fillHint: (mouseInfo)->
		(@timeline.config.icm?.fillHint ? @constructor.fillHint).call @, mouseInfo

	@fillHint: (mouseInfo)->
		if @isActive and mouseInfo.group?
			offset = mouseInfo.event.pageX - mouseInfo.parentOffset.left
			time = @timeline.approxTime @timeline.getTime(offset), @stateName is 'SetEnding'
			if time?
				@$hint.text moment.unix(time).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')
		else 
			@$hint.empty()

	placeHint: (mouseInfo)->
		(@timeline.config.icm?.placeHint ? @constructor.placeHint).call @, mouseInfo

	@placeHint: (mouseInfo)->
		if @isActive and mouseInfo.group?
			@$hint.appendTo TL.Misc.getScrollContainer mouseInfo.group.getView().$dom
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

	@ucFirst: (string)->
		string.charAt(0).toUpperCase() + string.slice 1

TL.registry = new class Registry
	constructor: ->
		@map = {}
		@lastOid = -1

	generateOid: ->
		++@lastOid

	get: (oid)->
		@map[oid]

	register: (object)->
		unless object.oid?
			object.oid = @generateOid()
			@map[object.oid] = object
		object.oid

	unregister: (oid)->
		delete @map[oid] if @map[oid]?

class TL.Registrable
	getOid: ->
		@oid

	init: ->
		TL.registry.register @

	deinit: ->
		TL.registry.unregister @oid

class TL.MultiViewed
	init: ->
		@views = {}
		@createViews()

	deinit: ->
		for name, view of @views
			view.$dom.remove()
			delete view.$dom
		delete @views

	createViews: ->
		@createView()

	createView: (type = 'default', parent, namePostfix)->
		name = type + (if namePostfix then ':' + namePostfix else '')
		@views[name] = {type, parent, $dom: @createViewDom parent, type}

	createViewDom: ->
		$('<div />')

	getView: (name = 'default')->
		@views[name]

	render: ->
		for name, view of @views
			@['render' + TL.Misc.ucFirst(view.type)].call @, view

class TL.Element extends TL.mixOf TL.Sized, TL.Registrable, TL.MultiViewed, TL.ResourceHolder
	constructor: (@timeline, @raw = {})->
		@className = @getClassName()
		super()
		@init()

	init: ->

	getClassName: ->
		@constructor.name.toLowerCase()

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

	getView: ->
		{type: 'default', @$dom}

class TL.Element.Root extends TL.Element
	getClassName: ->
		'root'

	createViews: ->
		@createView 'default', @timeline.container.getView()

	createViewDom: (parent)->
		TL.Misc.addDom 'root', parent.$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->

	placeDefault: (view)->
		view.$dom.css
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

	createViews: ->
		@createView 'default', @timeline.root.getView()

	createViewDom: (parent)->
		TL.Misc.addDom 'sidebar', parent.$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css if @timeline.config.ruler.position is 'top'
			top: @timeline.ruler.getOuterHeight()
			bottom: 0
		else 
			top: 0
			bottom: @timeline.ruler.getOuterHeight()

		view.$dom.css if @cfg().position is 'left'
			left: 0
			right: 'auto'
		else 
			left: 'auto'
			right: 0

		view.$dom.css 
			width: @getInnerWidth()

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

	createViews: ->
		@createView 'default', @timeline.root.getView()

	createViewDom: (parent)->
		$dom = TL.Misc.addDom 'ruler', parent.$dom
		TL.Misc.scrollize $dom, 'x', [{axis: 'x', getTarget: => group.getView().$dom for group in @timeline.groups}]
		$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css if @timeline.config.sidebar.position is 'left'
			left: @timeline.sidebar.getOuterWidth()
			right: 0
		else 
			left: 0
			right: @timeline.sidebar.getOuterWidth()

		view.$dom.css if @cfg().position is 'top'
			top: 0
			bottom: 'auto'
		else 
			top: 'auto'
			bottom: 0

		view.$dom.css 
			height: @timeline.ruler.getInnerHeight()

		TL.Misc.setInnerSize view.$dom, 
			x: TL.Misc.sum(range.getOuterWidth() for range in @timeline.ranges)
			y: @timeline.ruler.getInnerHeight()

class TL.Element.Corner extends TL.Element
	getClassName: ->
		'corner'

	createViews: ->
		@createView 'default', @timeline.root.getView()

	createViewDom: (parent)->
		TL.Misc.addDom 'corner', parent.$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css if @timeline.config.ruler.position is 'top'
			top: 0
			bottom: ''
		else
			top: ''
			bottom: 0

		view.$dom.css if @timeline.config.sidebar.position is 'left'
			left: 0
			right: ''
		else 
			left: ''
			right: 0
			
		view.$dom.css
			width: @timeline.sidebar.getOuterWidth()
			height: @timeline.ruler.getOuterHeight()

class TL.Element.Field extends TL.Element
	getClassName: ->
		'field'

	createViews: ->
		@createView 'default', @timeline.root.getView()

	createViewDom: (parent)->
		TL.Misc.addDom 'field', parent.$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css if @timeline.config.ruler.position is 'top'
			top: @timeline.ruler.getOuterHeight()
			bottom: 0
		else 
			top: 0
			bottom: @timeline.ruler.getOuterHeight()

		view.$dom.css if @timeline.config.sidebar.position is 'left'
			left: @timeline.sidebar.getOuterWidth()
			right: 0
		else 
			left: 0
			right: @timeline.sidebar.getOuterWidth()

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

	createViews: ->
		@createView 'default', @timeline.field.getView()
		@createView 'atSidebar', @timeline.sidebar.getView()

	createViewDom: (parent, type)->
		$dom = TL.Misc.addDom 'group', parent.$dom
		$dom.data 'timeline-host-object', @
		switch type
			when 'default'
				TL.Misc.scrollize $dom, 'xy', [
					{axis: 'x', getTarget: => 
						targets = (elseGroup.getView().$dom for elseGroup in @timeline.groups when elseGroup isnt @)
						targets.push $rulerDom if ($rulerDom = @timeline.ruler.getView().$dom)?
						targets
					},
					{axis: 'y', getTarget: => @getView('atSidebar')?.$dom ? null}
				]
			when 'atSidebar'
        $dom.on "click", ->
          object = $dom.data("timeline-host-object")
          ranges = object.timeline.ranges
          i = 0

          while i < ranges.length
            ranges[i].views.atRuler.$dom.empty()
            i++
          currentGroupLines = []
          otherLines = []
          object.timeline.lines.map (line) ->
            if object.getLines().indexOf(line) is -1
              currentGroupLines.push line
            else
              otherLines.push line
            return

          if object.raw.isHide
            object.timeline.lines = currentGroupLines.slice()
            otherLines[0].raw.lines.map (line) ->
              object.timeline.lines.push line  if object.timeline.lines.indexOf(line) is -1
              return

          else
            groupLine = {}
            for key of otherLines[0]
              groupLine[key] = otherLines[0][key]
            groupLine.raw.lines = []
            otherLines.map (line) ->
              groupLine.raw.lines.push line
              return

            object.timeline.lines = currentGroupLines.slice()
            object.timeline.lines.push groupLine
          object.raw.isHide = not object.raw.isHide
          object.timeline.render()
          return

        TL.Misc.scrollize $dom, 'y', [{axis: 'y', getTarget: => @getView().$dom}]

		$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css
			top : @getVerticalOffset()
			height: @getInnerHeight()

		TL.Misc.setInnerSize view.$dom, 
			x: TL.Misc.sum(range.getOuterWidth() for range in @timeline.ranges)
			y: TL.Misc.sum(line.getOuterHeight() for line in @getLines())

	renderAtSidebar: (view)->
		@fillAtSidebar view
		@placeAtSidebar view

	fillAtSidebar: (view)->
		@lookupProperty('fillAtSidebar').call @, view

	@fillAtSidebar: (view)->

	placeAtSidebar: (view)->
		@lookupProperty('placeAtSidebar').call @, view

	@placeAtSidebar: (view)->
		view.$dom.css
			top : @getVerticalOffset()
			height: @getInnerHeight()

		TL.Misc.setInnerSize view.$dom,
			x: @timeline.sidebar.getInnerWidth()
			y: TL.Misc.sum(line.getOuterHeight() for line in @getLines())

class TL.Element.Range extends TL.Element
	getClassName: ->
		'range'

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

	createViews: ->
		@createView 'default', group.getView(), "group=#{group.raw.id}" for group in @timeline.groups
		@createView 'atRuler', @timeline.ruler.getView()

	createViewDom: (parent)->
		TL.Misc.addDom 'range', parent.$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css
			left: @getOffset()
			width: @getInnerWidth()

	renderAtRuler: (view)->
		@fillAtRuler view
		@placeAtRuler view

	fillAtRuler: (view)->
		@lookupProperty('fillAtRuler').call @, view

	@fillAtRuler: (view) ->
		from = moment.unix(@raw.from).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')
		to = moment.unix(@raw.to).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')
		view.$dom.children('.tl-heading').remove()
		view.$dom.append TL.Misc.addDom('heading').text "#{from} — #{to}"

	placeAtRuler: (view)->
		@lookupProperty('placeAtRuler').call @, view

	@placeAtRuler: (view)->
		view.$dom.css
			left: @getOffset()
			width: @getInnerWidth()

class TL.Element.Dash extends TL.Element
	getClassName: ->
		'dash'

	getRule: ->
		@timeline.getDashRuleById @raw.ruleId

	createViews: ->
		@createView 'default', group.getView(), "group=#{group.raw.id}" for group in @timeline.groups
		@createView 'atRuler', @timeline.ruler.getView()

	createViewDom: (parent)->
		TL.Misc.addDom('dash', parent.$dom).addClass "id-#{@raw.ruleId}"

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		offset = @timeline.getOffset @raw.time
		if offset?
			view.$dom.css left: offset

	renderAtRuler: (view)->
		@fillAtRuler view
		@placeAtRuler view

	fillAtRuler: (view)->
		@lookupProperty('fillAtRuler').call @, view

	@fillAtRuler: (view)->
		view.$dom.children('.tl-text').remove()
		view.$dom.append TL.Misc.addDom('text').text moment.unix(@raw.time).tz(@timeline.config.timezone).format('HH:mm')

	placeAtRuler: (view)->
		@lookupProperty('placeAtRuler').call @, view

	@placeAtRuler: (view)->
		offset = @timeline.getOffset @raw.time
		if offset?
			view.$dom.css left: offset

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

	createViews: ->
		@createView 'default', @getGroup().getView()
		@createView 'atSidebar', @getGroup().getView 'atSidebar'

	createViewDom: (parent)->
		TL.Misc.addDom('line', parent.$dom).addClass "id-#{@raw.id}"

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		view.$dom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

	renderAtSidebar: (view)->
		@fillAtSidebar view
		@placeAtSidebar view

	fillAtSidebar: (view)->
		@lookupProperty('fillAtSidebar').call @, view

	@fillAtSidebar: (view)->
		view.$dom.children('.tl-heading').remove()
		view.$dom.append TL.Misc.addDom('heading').text @raw.id

	placeAtSidebar: (view)->
		@lookupProperty('placeAtSidebar').call @, view

	@placeAtSidebar: (view)->
		view.$dom.css
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

	isResizable: ->
		@lookupProperty 'isResizable', yes

	canCrossRanges: ->
		@lookupProperty 'canCrossRanges', yes

	createViews: ->
		@createView 'default', @getLine().getGroup().getView()

	createViewDom: (parent, type)->
		switch type
			when 'default'
				$dom = TL.Misc.addDom 'item', parent.$dom
				@makeDraggable $dom if @isDraggable()
				@makeResizeableLeft $dom if @isResizable()
				@makeResizeableRight $dom if @isResizable()
				$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->
		view.$dom.children('.tl-text').remove()
		view.$dom.append TL.Misc.addDom('text').text @raw.text

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		line = @getLine()
		offset = @timeline.getOffset @raw.from
		view.$dom.css
			top: line.getVerticalOffset() + line.getInternalVerticalOffset()
			height: line.getInnerHeight()
			left: offset
			width: @timeline.getOffset(@raw.to-1) - offset
	
	getClone: ->
		clone = $.extend {}, @
		clone.raw = $.extend {}, @raw
		clone

	makeDraggable: ($dom)->
		modified = null
		$dragHint = null
		holdPos = null

		$dom.draggable
			helper: =>
				TL.Misc.addDom('drag-helper').css
					width: $dom.css 'width'
					height: $dom.css 'height'
			start: (e, ui)=>
				$dragHint = TL.Misc.addDom 'drag-hint', @getLine().getGroup().getView().$dom
				modified = @getClone()
				domOffset = $dom.offset()
				holdPos = 
					left: e.pageX - domOffset.left
					top: e.pageY - domOffset.top
				@timeline.fireEvent 'item:drag:start', item: @
			stop: (e, ui)=>
				$dragHint.remove()
				$dragHint = null
				modified = null
				holdPos = null
				@timeline.fireEvent 'item:drag:stop', item: @
			drag: (e, ui)=>
				group = @getLine().getGroup()
				parentOffset = TL.Misc.getScrollContainer(group.getView().$dom).offset()
				drag = {event: e, parentOffset, holdPos}
				drag.domPos = 
					left: drag.event.pageX - drag.parentOffset.left - drag.holdPos.left
					top: drag.event.pageY - drag.parentOffset.top - drag.holdPos.top

				duration = @getDuration()
				modified.raw.from = @timeline.approxTime @timeline.getTime drag.domPos.left
				modified.raw.to = modified.raw.from + duration
				newLine = @timeline.getLineByVerticalOffset group, drag.event.pageY - drag.parentOffset.top
				modified.raw.lineId = newLine.raw.id if newLine
				
				unless modified.isValid()
					originalLeft = @timeline.getOffset @raw.from
					direction = Math.sign drag.domPos.left - originalLeft
					attemptLeft = drag.domPos.left
					while attemptLeft isnt originalLeft
						attemptLeft -= direction
						modified.raw.from = @timeline.approxTime @timeline.getTime attemptLeft
						modified.raw.to = modified.raw.from + duration
						break if modified.isValid()

				@renderDragHint $dragHint, drag, modified

				if modified.isValid()
					if @timeline.fireEvent('item:drag', item: modified, originalItem: @) and
					@timeline.fireEvent('item:modify', item: modified, originalItem: @)
						$.extend @raw, modified.raw
						@render()

	renderDragHint: ($dom, drag, modified)->
		@fillDragHint $dom, drag, modified
		@placeDragHint $dom, drag, modified

	fillDragHint: ($dom, drag, modified)->
		@lookupProperty('fillDragHint').call @, $dom, drag, modified

	@fillDragHint: ($dom, drag, modified)->
		time = if modified.isValid() then modified.raw.from else @raw.from
		if time?
			$dom.text moment.unix(time).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')

	placeDragHint: ($dom, drag, modified)->
		@lookupProperty('placeDragHint').call @, $dom, drag, modified

	@placeDragHint: ($dom, drag, modified)-> 
		$dom.css
			left: drag.event.pageX - drag.parentOffset.left
			top: drag.event.pageY - drag.parentOffset.top

	makeResizeableLeft: ($dom)->
		$resizerLeft = TL.Misc.addDom 'resizer-left', $dom
		$resizeHint = null
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
				$resizeHint = TL.Misc.addDom 'resize-hint', @getLine().getGroup().getView().$dom
				modified = @getClone()
				originalDomOffset = @timeline.getOffset @raw.from
				originalDomWidth = @timeline.getOffset(@raw.to - 1) - originalDomOffset
				@timeline.fireEvent 'item:resize:start', item: @
			stop: (e, ui)=>
				$resizeHint.remove()
				$resizeHint.null
				modified = null
				originalDomOffset = null
				originalDomWidth = null
				@timeline.fireEvent 'item:resize:stop', item: @
			drag: (e, ui)=>
				group = @getLine().getGroup()
				
				resizeInfo = 
					parentOffset: TL.Misc.getScrollContainer(group.getView().$dom).offset()
					event: e
					ui: ui
					left: originalDomOffset + (ui.position.left - ui.originalPosition.left)
					width: originalDomWidth - (ui.position.left - ui.originalPosition.left)
					side: 'left'

				$(ui.helper).css marginLeft: -(ui.position.left - ui.originalPosition.left)
				 
				@renderResizeHint $resizeHint, resizeInfo
				
				modified.raw.from = @timeline.approxTime @timeline.getTime resizeInfo.left
				
				if modified.isValid()
					if @timeline.fireEvent('item:resize', item: modified, originalItem: @) and
					@timeline.fireEvent('item:modify', item: modified, originalItem: @)
						$.extend @raw, modified.raw
						@render()

	makeResizeableRight: ($dom)->
		$resizerRight = TL.Misc.addDom 'resizer-right', $dom
		$resizeHint = null
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
				$resizeHint = TL.Misc.addDom 'resize-hint', @getLine().getGroup().getView().$dom
				modified = @getClone()
				originalDomOffset = @timeline.getOffset @raw.from
				originalDomWidth = @timeline.getOffset(@raw.to - 1) - originalDomOffset
				@timeline.fireEvent 'item:resize:start', item: @
			stop: (e, ui)=>
				$resizeHint.remove()
				$resizeHint = null
				modified = null
				originalDomOffset = null
				originalDomWidth = null
				@timeline.fireEvent 'item:resize:stop', item: @
			drag: (e, ui)=>
				group = @getLine().getGroup()
				
				resizeInfo = 
					parentOffset: TL.Misc.getScrollContainer(group.getView().$dom).offset()
					event: e
					ui: ui
					left: originalDomOffset
					width: originalDomWidth + (ui.position.left - ui.originalPosition.left)
					side: 'right'
				 
				@renderResizeHint $resizeHint, resizeInfo
				
				modified.raw.to = @timeline.approxTime @timeline.getTime(resizeInfo.left + resizeInfo.width), yes
				
				if modified.isValid()
					if @timeline.fireEvent('item:resize', item: modified, originalItem: @) and
					@timeline.fireEvent('item:modify', item: modified, originalItem: @)
						$.extend @raw, modified.raw
						@render()

	renderResizeHint: ($dom, resizeInfo)->
		@fillResizeHint $dom, resizeInfo
		@placeResizeHint $dom, resizeInfo

	fillResizeHint: ($dom, resizeInfo)->
		@lookupProperty('fillResizeHint').call @, $dom, resizeInfo

	@fillResizeHint: ($dom, resizeInfo)->
		offset = if resizeInfo.side is 'left'
			resizeInfo.left
		else 
			resizeInfo.left + resizeInfo.width

		time = @timeline.approxTime @timeline.getTime(offset), resizeInfo.side is 'right'
		if time?
			$dom.text moment.unix(time).tz(@timeline.config.timezone).format('DD.MM.YYYY HH:mm:ss')

	placeResizeHint: ($dom, resizeInfo)->
		@lookupProperty('placeResizeHint').call @, $dom, resizeInfo

	@placeResizeHint: ($dom, resizeInfo)-> 
		$dom.css
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

  i = 0
  while i < @timeline.items.length
    return no if @timeline.items[i].raw.lineId is @raw.lineId and @timeline.items[i].raw.to >= @raw.from
    i++
    
		yes

	remove: ->
		@timeline.items = @timeline.items.filter (item)=> @ isnt item
		@destructor()

class TL.Element.DashRule
	constructor: (@timeline, @raw = {})->
		@insertDashes()

	removeDashes: ->
		dash.remove() for dash in @timeline.dashes when @raw.id is dash.raw.ruleId

	insertDashes: ->
		@timeline.dashes = @timeline.dashes.concat @calculateDashes()

	calculateDashes: ->
		dashes = []
		step = @raw.step ? Infinity
		offset = @raw.offset ? 0

		for range in @timeline.ranges
			if step is Infinity
				time = offset
			else
				time = Math.floor(range.raw.from / step) * step + offset

			while time < range.raw.to
				if time >= range.raw.from and !@isTimeExcluded time
					dashes.push @timeline.createElement 'Dash', {time, ruleId: @raw.id}
				time += step

		dashes

	isTimeExcluded: (time)->
		if @raw.exclude?
			for excluderId in @raw.exclude
				if @timeline.getDashRuleById(excluderId).hasDashAtTime(time)
					return yes
		no

	hasDashAtTime: (time)->
		step = @raw.step ? Infinity
		offset = @raw.offset ? 0
		(time - offset) % step == 0

class TL.Element.Now extends TL.Element
	getClassName: ->
		'now'

	init: ->
		@interval = setInterval =>
			@raw.time = @timeline.getCurrentTime() 
			@render()
		, 1000

	deinit: ->
		clearInterval @interval

	createViews: ->
		@createView 'default', group.getView(), "group=#{group.raw.id}" for group in @timeline.groups
		@createView 'atRuler', @timeline.ruler.getView()

	createViewDom: (parent)->
		TL.Misc.addDom 'now', parent.$dom

	renderDefault: (view)->
		@fillDefault view
		@placeDefault view

	fillDefault: (view)->
		@lookupProperty('fillDefault').call @, view

	@fillDefault: (view)->

	placeDefault: (view)->
		@lookupProperty('placeDefault').call @, view

	@placeDefault: (view)->
		offset = @timeline.getOffset @raw.time
		if offset?
			view.$dom.show().css left: offset
		else
			view.$dom.hide()

	renderAtRuler: (view)->
		@fillAtRuler view
		@placeAtRuler view

	fillAtRuler: (view)->
		@lookupProperty('fillAtRuler').call @, view

	@fillAtRuler: (view)->

	placeAtRuler: (view)->
		@lookupProperty('placeAtRuler').call @, view

	@placeAtRuler: (view)->
		offset = @timeline.getOffset @raw.time
		if offset?
			view.$dom.show().css left: offset
		else 
			view.$dom.hide()