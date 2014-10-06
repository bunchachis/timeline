log = (x)-> console.log(x)

# All ranges is [from, to)

class Element
	constructor: (@raw, @timeline)->

	cfg: ->
		@timeline.config

class Group
	constructor: (group, timeline)->
		$.extend @, group
		@timeline = timeline

	getLines: ->
		line for line in @timeline.lines when line.groupId is @id

	getVerticalOffset: ->
		@timeline.arraySum(
			for elseGroup in @timeline.groups
				break if elseGroup.id is @id
				elseGroup.getOuterHeight() 
		)

	getInnerHeight: ->
		@height ? @timeline.config.group.height

	getOuterHeight: ->
		@getInnerHeight() +
		@timeline.config.group.extraOffset.before +
		@timeline.config.group.extraOffset.after

class Range
	constructor: (range, timeline)->
		$.extend @, range
		@timeline = timeline

	getOffset: ->
		@timeline.arraySum(
			for elseRange in @timeline.ranges when elseRange.from < @from
				elseRange.getOuterWidth() 
		)

	getInternalOffset: (time)->
		@getExtraOffsetBefore() +
		Math.ceil(time / @timeline.config.scale) - Math.ceil(@from / @timeline.config.scale)

	getInnerWidth: ->
		Math.ceil(@to / @timeline.config.scale) - Math.ceil(@from / @timeline.config.scale)

	getOuterWidth: ->
		@getInnerWidth() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getExtraOffsetBefore: ->
		@extraOffsetBefore ? @timeline.config.range.extraOffset.before

	getExtraOffsetAfter: ->
		@extraOffsetAfter ? @timeline.config.range.extraOffset.after

	getTimeByOffset: (offset)->
		@getTimeByInternalOffset(offset - @getOffset() - @getExtraOffsetBefore())

	getTimeByInternalOffset: (internalOffset)->
		@from + internalOffset * @timeline.config.scale

class Line
	constructor: (line, timeline)->
		$.extend @, line
		@timeline = timeline

	getVerticalOffset: ->
		@timeline.arraySum(
			for elseLine in @timeline.lines when elseLine.groupId is @groupId
				break if elseLine.id is @id
				elseLine.getOuterHeight() 
		)

	getInternalVerticalOffset: ->
		@getExtraOffsetBefore()	

	getInnerHeight: ->
		@height ? @timeline.config.line.height

	getOuterHeight: ->
		@getInnerHeight() +
		@getExtraOffsetBefore() +
		@getExtraOffsetAfter()

	getGroup: ->
		@timeline.getGroupById @.groupId

	getExtraOffsetBefore: ->
		@extraOffsetBefore ? @timeline.config.line.extraOffset.before

	getExtraOffsetAfter: ->
		@extraOffsetAfter ? @timeline.config.line.extraOffset.after

class Item extends Element
	getLine: ->
		@timeline.getLineById @raw.lineId

	getDuration: ->
		@raw.to - @raw.from

	isDraggable: ->
		@raw.isDraggable ? @cfg().item.isDraggable ? true

	canCrossRanges: ->
		@raw.canCrossRanges ? @cfg().item.canCrossRanges ? true

	build: ->
		@$dom = @timeline.addDom 'item', @getLine().getGroup().$fieldDom
		@render()
		@place()
		@makeDraggable()

	render: ->
		(@raw.render ? @cfg().item.render ? @constructor.render).call @

	@render: ->
		@$dom.empty().append @timeline.addDom('text').text @raw.text

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
				@$dragHint = @timeline.addDom 'drag-hint', @getLine().getGroup().$fieldDom
				modified = $.extend true, {}, @
			stop: (e, ui)=>
				@$dragHint.remove()
				modified = null
			drag: (e, ui)=>
				group = @getLine().getGroup()
				drag = 
					parentOffset: @timeline.getScrollContainer(group.$fieldDom).offset()
					event: e
					ui: ui
				
				@renderDragHint drag
				@placeDragHint drag
				
				duration = @getDuration()
				modified.raw.from = @timeline.approxTime @timeline.getTime drag.ui.position.left
				modified.raw.to = modified.raw.from + duration
				newLine = @timeline.getLineByVerticalOffset group, drag.event.pageY - drag.parentOffset.top
				modified.raw.lineId = newLine.id if newLine

				if modified.isValid() and @canChangeTo modified
					$.extend @raw, modified.raw
					@place()

	canChangeTo: (modified)->
		(@raw.canChangeTo ? @cfg().item.canChangeTo ? @constructor.canChangeTo).call @, modified

	@canChangeTo: (modified)->
		true

	isValid: ->
		rangeFrom = @timeline.getRangeByTime @raw.from
		return false if !rangeFrom?

		rangeTo = @timeline.getRangeByTime @raw.to - 1
		return false if !rangeTo?

		return false if !@canCrossRanges() and rangeFrom isnt rangeTo

		true

	renderDragHint: (drag)->
		(@raw.renderDragHint ? @cfg().item.renderDragHint ? @constructor.renderDragHint).call @, drag

	@renderDragHint: (drag)->
		time =  @timeline.approxTime @timeline.getTime drag.ui.position.left
		if time?
			@$dragHint.text moment.unix(time).format('DD.MM.YYYY HH:mm:ss')

	placeDragHint: (drag)->
		(@raw.placeDragHint ? @cfg().item.placeDragHint ? @constructor.placeDragHint).call @, drag

	@placeDragHint: (drag)-> 
		@$dragHint.css
			left: drag.event.pageX - drag.parentOffset.left
			top: drag.event.pageY - drag.parentOffset.top


class Timeline
	constructor: (container, config = {}, items = [])->
		@$container = $ container
		@config = $.extend true, @getDefaultConfig(), config
		
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

	addRange: (range)->
		for elseRange in @ranges
			if range.from < elseRange.to and range.to > elseRange.from 
				throw 'Can\'t add range overlapping existing one'

		@ranges.push new Range range, @
		@ranges = @ranges.sort (a, b)->
			a.from - b.from

	addGroup: (group)->
		for elseGroup in @groups
			if elseGroup.id is group.id
				throw 'Can\'t add group with same id as existing one has'

		@groups.push new Group group, @
		@groups = @groups.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	addLine: (line)->
		for elseLine in @lines
			if elseLine.id is line.id
				throw 'Can\'t add line with same id as existing one has'

		@lines.push new Line line, @
		@lines = @lines.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	addDashRule: (rule)->
		for elseRule in @dashRules
			if elseRule.id is rule.id
				throw 'Can\'t add dash rule with same id as existing one has'

		@dashRules.push rule
		@dashRules = @dashRules.sort (a, b)->
			(a.order ? 0) - (b.order ? 0)

	addItem: (obj)->
		item = new Item obj, @
		unless item.isValid()
			throw 'Can\'t add item due to its invalidity'

		@items.push item 

	getDefaultConfig: ->
		ruler:
			position: 'top'
			ranges:
				render: $.proxy @, 'renderRulerRange'
		sidebar:
			position: 'left'
			lines:
				render: $.proxy @, 'renderSidebarLine'
		field:
			lines:
				render: $.proxy @, 'renderFieldLine'
			ranges:
				render: $.proxy @, 'renderFieldRange'
		range:
			extraOffset: 
				before: 5
				after: 15
		group:
			height: 500
			extraOffset:
				before: 20
				after: 20
		line:
			height: 50
			extraOffset:
				before: 5
				after: 10
		item:
			isDraggable: true
			canCrossRanges: true
			render: null
		scale: 1
		dashRules: []
		ranges: []
		groups: []
		lines: []

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
			autoHideScrollbar: true
			axis: axis
			scrollInertia: 0
			mouseWheel:
				scrollAmount: 30
			callbacks: {}

		config.mouseWheel.axis = 'x' if axis is 'xy'

		if pairs.length
			config.callbacks.whileScrolling = ->
				for pair in pairs
					position = {}
					position.x = @mcs.left + 'px' if pair.axis.indexOf('x') > -1
					position.y = @mcs.top + 'px' if pair.axis.indexOf('y') > -1

					$targets = pair.getTarget()
					if $targets.length
						$.each $targets, ->
							$(@).mCustomScrollbar 'scrollTo', position,
								scrollInertia: 0
								timeout: 0
								callbacks: false

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

	build: ->
		@$root = @addDom 'root', @$container
		@buildSidebar()
		@buildRuler()
		@buildField()

	buildRuler: ->
		@$ruler = @addDom 'ruler', @$root
		@scrollize @$ruler, 'x', [{axis: 'x', getTarget: => group.$fieldDom for group in @groups}]
		@placeRuler()
		@buildRulerRanges()
		@buildRulerDashes()

	placeRuler: ->
		@setInnerSize @$ruler, 
			x: @arraySum(range.getOuterWidth() for range in @ranges)

	buildRulerRanges: ->
		@buildRulerRange range for range in @ranges

	buildRulerRange: (range)->
		$range = @addDom 'range', @$ruler
		render = range.rulerRender ? @config.ruler.ranges.render
		$range.html render range
		@placeRulerRange $range, range

	renderRulerRange: (range)->
		from = moment.unix(range.from).format('DD.MM.YYYY HH:mm:ss')
		to = moment.unix(range.to).format('DD.MM.YYYY HH:mm:ss')
		@addDom('heading').text "#{from} — #{to}"

	placeRulerRange: ($range, range)->
		$range.css
			left: range.getOffset()
			width: range.getInnerWidth()

	buildRulerDashes: ->
		@buildRulerDash dash for dash in @calcDashes()

	buildRulerDash: (dash)->
		dash.$rulerDom = @addDom 'dash', @$ruler
		dash.$rulerDom.addClass "id-#{dash.rule.id}"
		@placeRulerDash dash

	placeRulerDash: (dash)->
		offset = @getOffset dash.time
		if offset?
			dash.$rulerDom.css left: offset

	getOffset: (time)->	
		if time?
			range = @getRangeByTime time
			if range?
				range.getOffset() + range.getInternalOffset(time)

	getRangeByTime: (time)->
		for range in @ranges
			if range.from <= time < range.to
				return range

	calcDashes: ->
		dashes = []
		for dashRule in @dashRules 
			for range in @ranges
				if dashRule.type is 'every'
					dashes = dashes.concat @calcDashesEvery(range, dashRule)
		
		map = {}
		map[dash.time] = dash for dash in dashes when !map[dash.time]?

		dashes = []
		dashes.push dash for time, dash of map
		dashes

	calcDashesEvery: (range, rule)->
		dashes = []
		time = range.from
		while time < range.to
			dashes.push {time, rule}
			time += rule.step
		dashes

	buildSidebar: ->
		@$sidebar = @addDom 'sidebar', @$root
		@buildSidebarGroups()

	buildSidebarGroups: ->
		@buildSidebarGroup group for group in @groups

	buildSidebarGroup: (group)->
		group.$sidebarDom = @addDom 'group', @$sidebar
		@scrollize group.$sidebarDom, 'y', [{axis: 'y', getTarget: => group.$fieldDom}]
		@placeSidebarGroup group
		@buildSidebarLines group

	placeSidebarGroup: (group)->
		group.$sidebarDom.css
			top : group.getVerticalOffset()
			height: group.height

		@setInnerSize group.$sidebarDom,
			y: @arraySum(line.getOuterHeight() for line in group.getLines())

	buildSidebarLines: (group)->
		@buildSidebarLine line for line in group.getLines()

	buildSidebarLine: (line)->
		$line = @addDom 'line', line.getGroup().$sidebarDom
		render = line.sidebarRender ? @config.sidebar.lines.render
		$line.html render line
		@placeSidebarLine $line, line

	renderSidebarLine: (line)->
		@addDom('heading').text line.id

	placeSidebarLine: ($line, line)->
		$line.css
			top: line.getVerticalOffset()
			height: line.getInnerHeight()

	getLineById: (lineId)->
		for line in @lines
			if line.id is lineId
				return line

	getGroupById: (groupId)->
		for group in @groups
			if group.id is groupId
				return group

	buildField: ->
		@$field = @addDom 'field', @$root
		@buildFieldGroups()

	buildFieldGroups: ->
		@buildFieldGroup group for group in @groups

	buildFieldGroup: (group)->
		group.$fieldDom = @addDom 'group', @$field
		@scrollize group.$fieldDom, 'xy', [
			{axis: 'x', getTarget: => [@$ruler].concat(elseGroup.$fieldDom for elseGroup in @groups when elseGroup.id isnt group.id)},
			{axis: 'y', getTarget: => group.$sidebarDom}
		]
		@placeFieldGroup group
		@buildFieldLines group
		@buildFieldRanges group
		@buildFieldDashes group
		@buildFieldItems group

	placeFieldGroup: (group)->
		group.$fieldDom.css
			top : group.getVerticalOffset()
			height: group.height

		@setInnerSize group.$fieldDom, 
			x: @arraySum(range.getOuterWidth() for range in @ranges)
			y: @arraySum(line.getOuterHeight() for line in group.getLines())

	buildFieldLines: (group)->
		@buildFieldLine line for line in group.getLines()

	buildFieldLine: (line)->
		$line = @addDom 'line', line.getGroup().$fieldDom
		render = line.fieldRender ? @config.field.lines.render
		$line.html render line
		@placeFieldLine $line, line

	renderFieldLine: (line)->
		''

	placeFieldLine: ($line, line)->
		$line.css
			top: line.getVerticalOffset()
			height: line.getInnerHeight()

	buildFieldRanges: (group)->
		@buildFieldRange range, group for range in @ranges

	buildFieldRange: (range, group)->
		$range = @addDom 'range', group.$fieldDom
		render = range.fieldRender ? @config.field.ranges.render
		$range.html render range
		@placeFieldRange $range, range

	renderFieldRange: (range)->
		''

	placeFieldRange: ($range, range)->
		$range.css
			left: range.getOffset()
			width: range.getInnerWidth()

	buildFieldDashes: (group)->
		@buildFieldDash dash, group for dash in @calcDashes()

	buildFieldDash: (dash, group)->
		dash.$fieldDom = @addDom 'dash', group.$fieldDom
		dash.$fieldDom.addClass "id-#{dash.rule.id}"
		@placeFieldDash dash

	placeFieldDash: (dash)->
		offset = @getOffset dash.time
		if offset?
			dash.$fieldDom.css left: offset

	buildFieldItems: (group)->
		item.build() for item in @items when item.getLine().groupId is group.id

	approxOffset: (offset)->
		@getOffset @approxTime @getTime offset

	approxTime: (time)->
		if time?
			snapResolution = 6 * 60 * 60
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

	getTime: (offset)->
		range = @getRangeByOffset offset
		if range?
			range.getTimeByOffset offset

	getRangeByOffset: (offset)->
		for range in @ranges
			rangeStart = range.getOffset() + range.getInternalOffset(range.from)
			rangeEnd = rangeStart + range.getInnerWidth()
			if rangeStart <= offset < rangeEnd
				return range

	getLineByVerticalOffset: (group, verticalOffset)->
		for line in group.getLines()
			lineStart = line.getVerticalOffset() + line.getInternalVerticalOffset()
			lineEnd = lineStart + line.getInnerHeight()
			if lineStart <= verticalOffset < lineEnd
				return line

window.Timeline = Timeline