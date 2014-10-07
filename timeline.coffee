log = (x)-> console.log(x)

# All ranges is [from, to)

class Timeline
	constructor: (container, config = {}, items = [])->
		@$container = $ container
		@config = $.extend yes, @getDefaultConfig(), config

		@util = new Timeline.Util

		@sidebar = @createElement 'Sidebar'
		@ruler = @createElement 'Ruler'
		@field = @createElement 'Field'
		
		@ranges = []
		@addRange range for range in @config.ranges

		@groups = []
		@addGroup group for group in @config.groups

		@lines = []
		@addLine line for line in @config.lines

		@dashRules = []
		@addDashRule rule for rule in @config.dashRules

		@items = []
		@addItem item for item in items

		@build()

	createElement: (type, data = {})->
		new @constructor[type] @, data 

	addRange: (range)->
		for elseRange in @ranges
			if range.from < elseRange.raw.to and range.to > elseRange.raw.from 
				throw 'Can\'t add range overlapping existing one'

		@ranges.push @createElement 'Range', range
		@ranges = @ranges.sort (a, b)->
			a.raw.from - b.raw.from

	addGroup: (group)->
		for elseGroup in @groups
			if elseGroup.raw.id is group.id
				throw 'Can\'t add group with same id as existing one has'

		@groups.push @createElement 'Group', group
		@groups = @groups.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	addLine: (line)->
		for elseLine in @lines
			if elseLine.raw.id is line.id
				throw 'Can\'t add line with same id as existing one has'

		@lines.push @createElement 'Line', line
		@lines = @lines.sort (a, b)->
			(a.raw.order ? 0) - (b.raw.order ? 0)

	addDashRule: (rule)->
		for elseRule in @dashRules
			if elseRule.id is rule.id
				throw 'Can\'t add dash rule with same id as existing one has'

		@dashRules.push rule
		@dashRules = @dashRules.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	addItem: (obj)->
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
			height: 500
			extraOffset:
				before: 20
				after: 20
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
		dashRules: []
		ranges: []
		groups: []
		lines: []

	build: ->
		@$root = @util.addDom 'root', @$container
		@sidebar.build()
		@ruler.build()
		@field.build()

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

	approxOffset: (offset)->
		@getOffset @approxTime @getTime offset

	approxTime: (time)->
		if time?
			snapResolution = 3 * 60 * 60
			approxed = Math.round(time / snapResolution) * snapResolution
			if @getRangeByTime approxed
				approxed
			else
				approxed = Math.ceil(time / snapResolution) * snapResolution
				if @getRangeByTime approxed
					approxed
				else
					approxed = Math.floor(time / snapResolution) * snapResolution
					approxed if @getRangeByTime approxed

class Timeline.Util
	addDom: (name, $container)->
		$element = $('<div />').addClass "tl-#{name}"
		if $container
			$element.appendTo @getScrollContainer $container
		$element

	scrollize: ($element, axis, pairs = [])->
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

	getScrollContainer: ($element)->
		$inner = $element.data 'scroll-inner'

		if $inner?.length
			$inner
		else
			$element

	setInnerSize: ($element, size)->
		css = {}
		css.width = size.x if size.x
		css.height = size.y if size.y
		@getScrollContainer($element).css css
		$element.mCustomScrollbar 'update'

	arraySum: (array)->
		sum = 0
		sum += value for value in array
		sum

class Timeline.Element
	constructor: (@timeline, @raw = {})->
		@init()

	init: ->

	cfg: ->
		@timeline.config

	u: ->
		@timeline.util

class Timeline.Sidebar extends Timeline.Element
	isVisible: ->
		@raw.isVisible ? @cfg().sidebar.isVisible ? yes

	getOuterWidth: ->
		if @isVisible()
			@getInnerWidth()
		else
			0

	getInnerWidth: ->
		if @isVisible()
			@raw.width ? @cfg().sidebar.width ? 100
		else
			0

	build: ->
		@$dom = @u().addDom 'sidebar', @timeline.$root
		@render()
		@place()

		@buildGroups()

	render: ->
		(@raw.render ? @cfg().sidebar.render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().sidebar.place ? @constructor.place).call @

	@place: ->
		@$dom.css if @cfg().ruler.position is 'top'
			top: @timeline.ruler.getOuterHeight()
			bottom: 0
		else 
			top: 0
			bottom: @timeline.ruler.getOuterHeight()

		@$dom.css if @cfg().sidebar.position is 'left'
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
	isVisible: ->
		@raw.isVisible ? @cfg().ruler.isVisible ? yes

	getOuterHeight: ->
		if @isVisible()
			@getInnerHeight()
		else
			0

	getInnerHeight: ->
		if @isVisible()
			@raw.height ? @cfg().ruler.height ? 50
		else
			0

	build: ->
		@$dom = @u().addDom 'ruler', @timeline.$root
		@u().scrollize @$dom, 'x', [{axis: 'x', getTarget: => group.$dom for group in @timeline.groups}]
		@render()
		@place()
		
		@buildRanges()
		@buildDashes()

	render: ->
		(@raw.render ? @cfg().ruler.render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().ruler.place ? @constructor.place).call @

	@place: ->
		@$dom.css if @cfg().sidebar.position is 'left'
			left: @timeline.sidebar.getOuterWidth()
			right: 0
		else 
			left: 0
			right: @timeline.sidebar.getOuterWidth()

		@$dom.css if @cfg().ruler.position is 'top'
			top: 0
			bottom: 'auto'
		else 
			top: 'auto'
			bottom: 0

		@$dom.css 
			height: @timeline.ruler.getInnerHeight()

		@u().setInnerSize @$dom, 
			x: @u().arraySum(range.getOuterWidth() for range in @timeline.ranges)
			y: @timeline.ruler.getInnerHeight()

	buildRanges: ->
		range.buildAtRuler() for range in @timeline.ranges

	buildDashes: ->
		dash.buildAtRuler() for dash in @timeline.calcDashes()

class Timeline.Field extends Timeline.Element
	build: ->
		@$dom = @u().addDom 'field', @timeline.$root
		@render()
		@place()

		@buildGroups()

	render: ->
		(@raw.render ? @cfg().field.render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().field.place ? @constructor.place).call @

	@place: ->
		@$dom.css if @cfg().ruler.position is 'top'
			top: @timeline.ruler.getOuterHeight()
			bottom: 0
		else 
			top: 0
			bottom: @timeline.ruler.getOuterHeight()

		@$dom.css if @cfg().sidebar.position is 'left'
			left: @timeline.sidebar.getOuterWidth()
			right: 0
		else 
			left: 0
			right: @timeline.sidebar.getOuterWidth()

	buildGroups: ->
		group.build() for group in @timeline.groups

class Timeline.Group extends Timeline.Element
	getLines: ->
		line for line in @timeline.lines when line.raw.groupId is @raw.id

	getVerticalOffset: ->
		x = @u().arraySum(
			for elseGroup in @timeline.groups
				break if elseGroup.raw.id is @raw.id
				elseGroup.getOuterHeight() 
		)

	getInnerHeight: ->
		@raw.height ? @cfg().group.height

	getOuterHeight: ->
		@getInnerHeight() +
		@cfg().group.extraOffset.before +
		@cfg().group.extraOffset.after

	build: ->
		@$dom = @u().addDom 'group', @timeline.field.$dom
		@u().scrollize @$dom, 'xy', [
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
		(@raw.render ? @cfg().group.render ? @constructor.render).call @

	@render: ->

	place: ->
		(@raw.place ? @cfg().group.place ? @constructor.place).call @

	@place: ->
		@$dom.css
			top : @getVerticalOffset()
			height: @raw.height

		@u().setInnerSize @$dom, 
			x: @u().arraySum(range.getOuterWidth() for range in @timeline.ranges)
			y: @u().arraySum(line.getOuterHeight() for line in @getLines())

	buildLines: ->
		line.build() for line in @getLines()

	buildRanges: ->
		range.build @ for range in @timeline.ranges

	buildDashes: ->
		dash.build @ for dash in @timeline.calcDashes()

	buildItems: ->
		item.build() for item in @timeline.items when item.getLine().raw.groupId is @raw.id

	buildAtSidebar: ->
		@$sidebarDom = @u().addDom 'group', @timeline.sidebar.$dom
		@u().scrollize @$sidebarDom, 'y', [{axis: 'y', getTarget: => @$dom}]
		@renderAtSidebar()
		@placeAtSidebar()

		@buildLinesAtSidebar()

	renderAtSidebar: ->
		(@raw.renderAtSidebar ? @cfg().group.renderAtSidebar ? @constructor.renderAtSidebar).call @

	@renderAtSidebar: ->

	placeAtSidebar: ->
		(@raw.placeAtSidebar ? @cfg().group.placeAtSidebar ? @constructor.placeAtSidebar).call @

	@placeAtSidebar: ->
		@$sidebarDom.css
			top : @getVerticalOffset()
			height: @raw.height

		@u().setInnerSize @$sidebarDom,
			x: @timeline.sidebar.getInnerWidth()
			y: @u().arraySum(line.getOuterHeight() for line in @getLines())

	buildLinesAtSidebar: ->
		line.buildAtSidebar() for line in @getLines()

class Timeline.Range extends Timeline.Element
	init: ->
		@$doms = []

	getOffset: ->
		@u().arraySum(
			for elseRange in @timeline.ranges when elseRange.raw.from < @raw.from
				elseRange.getOuterWidth() 
		)

	getInternalOffset: (time)->
		@getExtraOffsetBefore() +
		Math.ceil(time / @cfg().scale) - Math.ceil(@raw.from / @cfg().scale)

	getInnerWidth: ->
		Math.ceil(@raw.to / @cfg().scale) - Math.ceil(@raw.from / @cfg().scale)

	getOuterWidth: ->
		@getInnerWidth() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getExtraOffsetBefore: ->
		@raw.extraOffsetBefore ? @cfg().range.extraOffset.before

	getExtraOffsetAfter: ->
		@raw.extraOffsetAfter ? @cfg().range.extraOffset.after

	getTimeByOffset: (offset)->
		@getTimeByInternalOffset(offset - @getOffset() - @getExtraOffsetBefore())

	getTimeByInternalOffset: (internalOffset)->
		@raw.from + internalOffset * @cfg().scale

	build: (group)->
		$dom = @u().addDom 'range', group.$dom
		@$doms.push $dom
		@render $dom
		@place $dom

	render: ($dom)->
		(@raw.render ? @cfg().range.render ? @constructor.render).call @, $dom

	@render: ($dom)->

	place: ($dom)->
		(@raw.place ? @cfg().range.place ? @constructor.place).call @, $dom

	@place: ($dom)->
		$dom.css
			left: @getOffset()
			width: @getInnerWidth()

	buildAtRuler: ->
		@$rulerDom = @u().addDom 'range', @timeline.ruler.$dom
		@renderAtRuler()
		@placeAtRuler()

	renderAtRuler: ->
		(@raw.renderAtRuler ? @cfg().range.renderAtRuler ? @constructor.renderAtRuler).call @

	@renderAtRuler: ->
		from = moment.unix(@raw.from).format('DD.MM.YYYY HH:mm:ss')
		to = moment.unix(@raw.to).format('DD.MM.YYYY HH:mm:ss')
		@$rulerDom.empty().append @u().addDom('heading').text "#{from} — #{to}"

	placeAtRuler: ->
		(@raw.placeAtRuler ? @cfg().range.placeAtRuler ? @constructor.placeAtRuler).call @

	@placeAtRuler: ->
		@$rulerDom.css
			left: @getOffset()
			width: @getInnerWidth()


class Timeline.Dash extends Timeline.Element
	init: ->
		@$doms = []

	build: (group)->
		$dom = @u().addDom 'dash', group.$dom
		$dom.addClass "id-#{@raw.rule.id}"
		@$doms.push $dom
		@render $dom
		@place $dom

	render: ($dom)->
		(@raw.render ? @cfg().dash.render ? @constructor.render).call @, $dom

	@render: ($dom)->
		$dom.empty()

	place: ($dom)->
		(@raw.place ? @cfg().dash.place ? @constructor.place).call @, $dom

	@place: ($dom)->
		offset = @timeline.getOffset @raw.time
		if offset?
			$dom.css left: offset

	buildAtRuler: (dash)->
		@$rulerDom = @u().addDom 'dash', @timeline.ruler.$dom
		@$rulerDom.addClass "id-#{@raw.rule.id}"
		@renderAtRuler()
		@placeAtRuler()

	renderAtRuler: ->
		(@raw.renderAtRuler ? @cfg().dash.renderAtRuler ? @constructor.renderAtRuler).call @

	@renderAtRuler: ->

	placeAtRuler: ->
		(@raw.placeAtRuler ? @cfg().dash.placeAtRuler ? @constructor.placeAtRuler).call @

	@placeAtRuler: ->
		offset = @timeline.getOffset @raw.time
		if offset?
			@$rulerDom.css left: offset

class Timeline.Line extends Timeline.Element
	getVerticalOffset: ->
		@u().arraySum(
			for elseLine in @timeline.lines when elseLine.raw.groupId is @raw.groupId
				break if elseLine.raw.id is @raw.id
				elseLine.getOuterHeight() 
		)

	getInternalVerticalOffset: ->
		@getExtraOffsetBefore()	

	getInnerHeight: ->
		@raw.height ? @cfg().line.height

	getOuterHeight: ->
		@getInnerHeight() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getGroup: ->
		@timeline.getGroupById @raw.groupId

	getExtraOffsetBefore: ->
		@raw.extraOffsetBefore ? @cfg().line.extraOffset.before

	getExtraOffsetAfter: ->
		@raw.extraOffsetAfter ? @cfg().line.extraOffset.after

	build: ->
		@$dom = @u().addDom 'line', @getGroup().$dom
		@render()
		@place()

	render: ->
		(@raw.render ? @cfg().line.render ? @constructor.render).call @

	@render: ->
		@$dom.empty()

	place: ->
		(@raw.place ? @cfg().line.place ? @constructor.place).call @

	@place: ->
		@$dom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

	buildAtSidebar: ->
		@$sidebarDom = @u().addDom 'line', @getGroup().$sidebarDom
		@renderAtSidebar()
		@placeAtSidebar()

	renderAtSidebar: ->
		(@raw.renderAtSidebar ? @cfg().line.renderAtSidebar ? @constructor.renderAtSidebar).call @

	@renderAtSidebar: ->
		@$sidebarDom.empty().append @u().addDom('heading').text @raw.id

	placeAtSidebar: ->
		(@raw.placeAtSidebar ? @cfg().line.placeAtSidebar ? @constructor.placeAtSidebar).call @

	@placeAtSidebar: ->
		@$sidebarDom.css
			top: @getVerticalOffset()
			height: @getInnerHeight()

class Timeline.Item extends Timeline.Element
	getLine: ->
		@timeline.getLineById @raw.lineId

	getDuration: ->
		@raw.to - @raw.from

	isDraggable: ->
		@raw.isDraggable ? @cfg().item.isDraggable ? yes

	canCrossRanges: ->
		@raw.canCrossRanges ? @cfg().item.canCrossRanges ? yes

	build: ->
		@$dom = @u().addDom 'item', @getLine().getGroup().$dom
		@render()
		@place()
		@makeDraggable()

	render: ->
		(@raw.render ? @cfg().item.render ? @constructor.render).call @

	@render: ->
		@$dom.empty().append @u().addDom('text').text @raw.text

	place: ->
		(@raw.place ? @cfg().item.place ? @constructor.place).call @

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
				$('<div />').css
					width: @$dom.css 'width'
					height: @$dom.css 'height'
			start: (e, ui)=>
				@$dragHint = @u().addDom 'drag-hint', @getLine().getGroup().$dom
				modified = $.extend yes, {}, @
			stop: (e, ui)=>
				@$dragHint.remove()
				modified = null
			drag: (e, ui)=>
				group = @getLine().getGroup()
				dragInfo = 
					parentOffset: @u().getScrollContainer(group.$dom).offset()
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

	canChangeTo: (modified)->
		(@raw.canChangeTo ? @cfg().item.canChangeTo ? @constructor.canChangeTo).call @, modified

	@canChangeTo: (modified)->
		yes

	isValid: ->
		rangeFrom = @timeline.getRangeByTime @raw.from
		return no if !rangeFrom?

		rangeTo = @timeline.getRangeByTime @raw.to - 1
		return no if !rangeTo?

		return no if !@canCrossRanges() and rangeFrom isnt rangeTo

		yes

	renderDragHint: (dragInfo)->
		(@raw.renderDragHint ? @cfg().item.renderDragHint ? @constructor.renderDragHint).call @, dragInfo

	@renderDragHint: (dragInfo)->
		time =  @timeline.approxTime @timeline.getTime dragInfo.ui.position.left
		if time?
			@$dragHint.text moment.unix(time).format('DD.MM.YYYY HH:mm:ss')

	placeDragHint: (dragInfo)->
		(@raw.placeDragHint ? @cfg().item.placeDragHint ? @constructor.placeDragHint).call @, dragInfo

	@placeDragHint: (dragInfo)-> 
		@$dragHint.css
			left: drag.event.pageX - drag.parentOffset.left
			top: drag.event.pageY - drag.parentOffset.top


window.Timeline = Timeline