# frozen_string_literal: true

module Capybara::Apparition
  module DevToolsProtocol
    class RemoteObject
      attr_reader :params

      def initialize(page, params)
        @params = params
        @page = page
      end

      def value
        cyclic_checked_value({})
      end

    protected

      def cyclic_checked_value(object_cache)
        if object?
          if array?
            extract_properties_array(get_remote_object(id), object_cache)
          elsif node?
            params
          elsif date?
            res = get_date_string(id)
            DateTime.parse(res)
          elsif window_class?
            { object_id: id }
          elsif validity_state?
            extract_properties_object(get_remote_object(id, false), object_cache)
          elsif object_class? || css_style? || classname?
            extract_properties_object(get_remote_object(id), object_cache)
          else
            params['value']
          end
        else
          params['value']
        end
      end

    private

      def object?; type == 'object' end
      def array?; subtype == 'array' end
      def date?; subtype == 'date' end
      def node?; subtype == 'node' end
      def object_class?; classname == 'Object' end
      def css_style?; classname == 'CSSStyleDeclaration' end
      def window_class?; classname == 'Window' end
      def validity_state?; classname == 'ValidityState' end
      def classname?; !classname.nil? end

      def type; params['type'] end
      def subtype; params['subtype'] end
      def id; params['objectId'] end
      def classname; params['className'] end

      def extract_properties_array(properties, object_cache)
        properties.reject { |prop| prop['name'] == 'apparitionId' }
                  .each_with_object([]) do |property, ary|
          # TODO: We may need to release these objects
          next unless property['enumerable']

          if property.dig('value', 'subtype') == 'node' # performance shortcut
            ary.push(property['value'])
          else
            ary.push(RemoteObject.new(@page, property['value']).cyclic_checked_value(object_cache))
          end
        end
      end

      def extract_properties_object(properties, object_cache)
        apparition_id = properties&.find { |prop| prop['name'] == 'apparitionId' }
                                  &.dig('value', 'value')

        result = if apparition_id
          return '(cyclic structure)' if object_cache.key?(apparition_id)

          object_cache[apparition_id] = {}
        end

        properties.reject { |prop| prop['name'] == 'apparitionId' }
                  .each_with_object(result || {}) do |property, hsh|
          # TODO: We may need to release these objects
          next unless property['enumerable']

          hsh[property['name']] = RemoteObject.new(@page, property['value']).cyclic_checked_value(object_cache)
        end
      end

      def get_remote_object(id, own_props = true)
        res = @page.session.connection.runtime.get_properties(
          _session_id: @page.session.id,
          object_id: id,
          own_properties: own_props
        )
        res[:result]
      end

      def get_date_string(id)
        @page.session.connection.runtime.call_function_on(
          _session_id: @page.session.id,
          function_declaration: 'function(){ return this.toUTCString() }',
          object_id: id,
          return_by_value: true
        )[:result].dig('value')
      end
    end
  end
end
