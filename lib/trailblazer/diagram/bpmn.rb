require "representable"
require "representable/xml"

require "trailblazer/developer/activity"

module Trailblazer
  module Diagram
    module BPMN
        Plane  = Struct.new(:element, :shapes, :edges)
        Shape  = Struct.new(:id, :element, :bounds)
        Edge   = Struct.new(:id, :element, :waypoints)
        Bounds = Struct.new(:x, :y, :width, :height)
        Waypoint = Struct.new(:x, :y)

      # Render an `Activity`'s circuit to a BPMN 2.0 XML `<process>` structure.
      def self.to_xml(activity, sequence, *args)
        # convert circuit to representable data structure.
        model, graph = Trailblazer::Developer::Activity.to_model(activity, *args)

        # require "pp"
        # pp model

        # raise "something wrong!" if model.task.size != sequence.size

        linear_tasks = sequence.collect { |row| row[:id] } # [:a, :b, :bb, :c, :d, :e, :f], in correct order.

        linear_tasks -= model.end_events.collect { |row| row[:id] } # FIXME: we should simply traverse the graph.

        start_x = 200
        y_right = 200
        y_left  = 300


        event_width = 54

        shape_width  = 81
        shape_height = 54
        shape_to_shape = 45

        current = start_x
        shapes = []

        # add start.
        shapes << Shape.new("Shape_#{model.start_events[0][:id]}", model.start_events[0][:id], Bounds.new(current, y_right, event_width, event_width))
        current += event_width+shape_to_shape

        # add tasks.
        linear_tasks.each do |name| # DISCUSS: assuming that task is in correct linear order.
          task = model.task.find { |t| t[:id] == name }
          warn "ignoring #{name}" && next if task.nil? # edges in sequence, not cool.

          is_right = [:pass, :step].include?( task.options[:created_by] )

          shapes << Shape.new("Shape_#{task[:id]}", task[:id], Bounds.new(current, is_right ? y_right : y_left , shape_width, shape_height))
          current += shape_width+shape_to_shape
        end

        # add ends.
        horizontal_end_offset = 90

        defaults = {
          "End.success" => { y: y_right },
          "End.failure" => { y: y_left },
          "End.pass_fast" => { y: y_right-90 },
          "End.fail_fast" => { y: y_left+90 },
        }


        # raise "@@@@@ #{model.end_events.last.name.inspect}"
        success_end_events = []
        failure_end_events = []

        model.end_events.each do |evt|
          id = evt[:id]
          y  = defaults[id] ? defaults[id][:y] : success_end_events.last + horizontal_end_offset

          success_end_events << y

          shapes << Shape.new( "Shape_#{id}", id, Bounds.new(current, y, event_width, event_width) )
        end
        # shapes << Shape.new("Shape_#{model.end_events[1][:id]}", model.end_events[1][:id], Bounds.new(current, y_left,  shape_width, shape_width))

        # shapes << Shape.new("Shape_#{model.end_events[2][:id]}", model.end_events[2][:id], Bounds.new(current, y_right-90, shape_width, shape_width))
        # shapes << Shape.new("Shape_#{model.end_events[3][:id]}", model.end_events[3][:id], Bounds.new(current, y_left+90,  shape_width, shape_width))


        edges = []
        model.sequence_flow.each do |flow|
          source = shapes.find { |shape| shape.id == "Shape_#{flow.sourceRef}" }.bounds
          target = shapes.find { |shape| shape.id == "Shape_#{flow.targetRef}" }.bounds

          edges << Edge.new("SequenceFlow_#{flow[:id]}", flow[:id], Path(source, target, target.x != current))
        end

        diagram = Struct.new(:plane).new(Plane.new(model.id, shapes, edges))

        # start_events = model.start_events.collect { |evt| Task.new(  ) }

        # model = Model.new()


        # render XML.
        Representer::Definitions.new(Definitions.new(model, diagram)).to_xml
      end




      def self.Path(source, target, do_straight_line)
        if source.y == target.y # --->
          [ Waypoint.new(*fromRight(source)), Waypoint.new(*toLeft(target))]
        else
          if do_straight_line
            [ Waypoint.new(*fromBottom(source)), Waypoint.new(*toLeft(target)) ]
          elsif target.y > source.y # target below source.
            [ l = Waypoint.new(*fromBottom(source)), r=Waypoint.new(l.x, target.y+target.height/2), Waypoint.new(target.x, r.y) ]
          else # target above source.
            [ l = Waypoint.new(*fromTop(source)), r=Waypoint.new(l.x, target.y+target.height/2), Waypoint.new(target.x, r.y) ]
          end
        end
      end
      def self.fromRight(left)
        [ left.x + left.width, left.y + left.height/2 ]
      end
      def self.toLeft(bounds)
        [ bounds.x, bounds.y + bounds.height/2 ]
      end
      def self.fromBottom(bounds)
        [ bounds.x + bounds.width/2, bounds.y+bounds.height ]
      end
      def self.fromTop(bounds)
        [ bounds.x + bounds.width/2, bounds.y ]
      end

      Definitions = Struct.new(:process, :diagram)

      # Representers for BPMN XML.
      module Representer
        class Task < Representable::Decorator
          include Representable::XML
          include Representable::XML::Namespace
          namespace "http://www.omg.org/spec/BPMN/20100524/MODEL"

          self.representation_wrap = :task # overridden via :as.

          property :id,   attribute: true
          property :name, attribute: true

          collection :outgoing, exec_context: :decorator
          collection :incoming, exec_context: :decorator

          def outgoing
            represented.outgoing.collect { |edge| edge[:id] }
          end

          def incoming
            represented.incoming.collect { |edge| edge[:id] }
          end
        end

        class SequenceFlow < Representable::Decorator
          include Representable::XML
          include Representable::XML::Namespace
          self.representation_wrap = :sequenceFlow
          namespace "http://www.omg.org/spec/BPMN/20100524/MODEL"

          property :id,   attribute: true
          property :sourceRef, attribute: true, exec_context: :decorator
          property :targetRef, attribute: true, exec_context: :decorator
          property :direction, as: :conditionExpression

          def sourceRef
            represented.sourceRef
          end

          def targetRef
            represented.targetRef
          end
        end

        class Process < Representable::Decorator
          include Representable::XML
          include Representable::XML::Namespace
          self.representation_wrap = :process

          namespace "http://www.omg.org/spec/BPMN/20100524/MODEL"

          property :id, attribute: true

          collection :start_events, as: :startEvent, decorator: Task
          collection :end_events, as: :endEvent, decorator: Task
          collection :task, decorator: Task
          collection :sequence_flow, decorator: SequenceFlow, as: :sequenceFlow
        end


        module Diagram
          class Bounds < Representable::Decorator
            include Representable::XML
            include Representable::XML::Namespace
            self.representation_wrap = :Bounds

            namespace "http://www.omg.org/spec/DD/20100524/DC"

            property :x,      attribute: true
            property :y,      attribute: true
            property :width,  attribute: true
            property :height, attribute: true
          end

          class Diagram < Representable::Decorator
            feature Representable::XML
            feature Representable::XML::Namespace
            self.representation_wrap = :BPMNDiagram

            namespace "http://www.omg.org/spec/BPMN/20100524/DI"

            property :plane, as: "BPMNPlane" do
              self.representation_wrap = :plane

              property :element, as: :bpmnElement, attribute: true

              namespace "http://www.omg.org/spec/BPMN/20100524/DI"

              collection :shapes, as: "BPMNShape" do
                self.representation_wrap = :BPMNShape
                namespace "http://www.omg.org/spec/BPMN/20100524/DI"

                property :id,                        attribute: true
                property :element, as: :bpmnElement, attribute: true

                property :bounds, as: "Bounds", decorator: Bounds
              end

              collection :edges,  as: "BPMNEdge" do
                self.representation_wrap = :BPMNEdge
                namespace "http://www.omg.org/spec/BPMN/20100524/DI"

                property :id,                        attribute: true
                property :element, as: :bpmnElement, attribute: true

                # <di:waypoint xsi:type="dc:Point" x="136" y="118" />
                collection :waypoints, as: :waypoint do
                  namespace "http://www.omg.org/spec/DD/20100524/DI"

                  property :type, as: "xsi:type", exec_context: :decorator, attribute: true
                  property :x, attribute: true
                  property :y, attribute: true

                  def type; "dc:Point" end
                end
              end
            end

            # namespace "http://www.w3.org/2001/XMLSchema-instance" # xsi
          end
        end



        class Definitions < Representable::Decorator
          include Representable::XML
          include Representable::XML::Namespace
          self.representation_wrap = :definitions

          namespace "http://www.omg.org/spec/BPMN/20100524/MODEL"
          namespace_def bpmn: "http://www.omg.org/spec/BPMN/20100524/MODEL"
          namespace_def bpmndi: "http://www.omg.org/spec/BPMN/20100524/DI"
          namespace_def di: "http://www.omg.org/spec/DD/20100524/DI"

          namespace_def dc: "http://www.omg.org/spec/DD/20100524/DC" # <cd:Bounds>
          namespace_def xsi: "http://www.w3.org/2001/XMLSchema-instance" # used in waypoint.

          property :process, decorator: Process
          property :diagram, decorator: Diagram::Diagram, as: :BPMNDiagram
        end
      end
    end
  end
end


# <bpmndi:BPMNDiagram id="BPMNDiagram_1">
#   <bpmndi:BPMNPlane id="BPMNPlane_1">
#      <bpmndi:BPMNShape id="_BPMNShape_Task_2" bpmnElement="Task_2">
#         <dc:Bounds x="100" y="100" width="36" height="36" />
#      </bpmndi:BPMNShape>
#      <bpmndi:BPMNShape id="_BPMNShape_Task_3" bpmnElement="Task_3">
#         <dc:Bounds x="236" y="78" width="100" height="80" />
#      </bpmndi:BPMNShape>
#      <bpmndi:BPMNEdge id="_BPMNConnection_Flow_4" bpmnElement="Flow_4">
#         <di:waypoint xsi:type="dc:Point" x="136" y="118" />
#         <di:waypoint xsi:type="dc:Point" x="236" y="118" />
#      </bpmndi:BPMNEdge>
#      <bpmndi:BPMNShape id="_BPMNShape_Task_5" bpmnElement="Task_5">
#         <dc:Bounds x="436" y="78" width="100" height="80" />
#      </bpmndi:BPMNShape>
#      <bpmndi:BPMNEdge id="_BPMNConnection_Flow_6" bpmnElement="Flow_6">
#         <di:waypoint xsi:type="dc:Point" x="336" y="118" />
#         <di:waypoint xsi:type="dc:Point" x="436" y="118" />
#      </bpmndi:BPMNEdge>
#      <bpmndi:BPMNShape id="_BPMNShape_Task_1" bpmnElement="Task_1">
#         <dc:Bounds x="636" y="100" width="36" height="36" />
#      </bpmndi:BPMNShape>
#      <bpmndi:BPMNShape id="_BPMNShape_Task_8" bpmnElement="Task_8">
#         <dc:Bounds x="636" y="266" width="100" height="80" />
#      </bpmndi:BPMNShape>
#      <bpmndi:BPMNEdge id="_BPMNConnection_Flow_7" bpmnElement="Flow_7">
#         <di:waypoint xsi:type="dc:Point" x="536" y="118" />
#         <di:waypoint xsi:type="dc:Point" x="636" y="118" />
#      </bpmndi:BPMNEdge>
#      <bpmndi:BPMNEdge id="_BPMNConnection_Flow_9" bpmnElement="Flow_9">
#         <di:waypoint xsi:type="dc:Point" x="536" y="118" />
#         <di:waypoint xsi:type="dc:Point" x="586" y="118" />
#         <di:waypoint xsi:type="dc:Point" x="586" y="306" />
#         <di:waypoint xsi:type="dc:Point" x="636" y="306" />
#      </bpmndi:BPMNEdge>
#      <bpmndi:BPMNEdge id="_BPMNConnection_Flow_10" bpmnElement="Flow_10">
#         <di:waypoint xsi:type="dc:Point" x="686" y="266" />
#         <di:waypoint xsi:type="dc:Point" x="686" y="201" />
#         <di:waypoint xsi:type="dc:Point" x="654" y="201" />
#         <di:waypoint xsi:type="dc:Point" x="654" y="136" />
#      </bpmndi:BPMNEdge>
#   </bpmndi:BPMNPlane>
# </bpmndi:BPMNDiagram>
