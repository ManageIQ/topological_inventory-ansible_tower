require 'concurrent'

module TopologicalInventory
  module AnsibleTower
    class Collector
      class Scheduler
        attr_accessor :full_refresh_frequency,
                      :partial_refresh_frequency

        def self.default
          @default ||= new
        end

        def self.configure
          if block_given?
            yield(default)
          else
            default
          end
        end

        def initialize
          self.full_refresh_frequency    = (ENV['COLLECTOR_FULL_REFRESH_FREQUENCY'] || 3600).to_i
          self.timestamps                = Concurrent::Map.new
          self.partial_refresh_frequency = (ENV['COLLECTOR_PARTIAL_REFRESH_FREQUENCY'] || 300).to_i
        end

        def add_source(source_uid)
          timestamps.put_if_absent(source_uid, {:full_refresh => {}, :partial_refresh => {}})
        end

        def remove_source(source_uid)
          timestamps.delete(source_uid)
        end

        def do_refresh?(source_uid)
          do_full_refresh?(source_uid) || do_partial_refresh?(source_uid)
        end

        def do_full_refresh?(source_uid)
          return true if timestamps[source_uid].try(:[], :full_refresh).nil?

          timestamps[source_uid][:full_refresh][:last_finished_at].nil? ||
            timestamps[source_uid][:full_refresh][:last_finished_at] < full_refresh_frequency.seconds.ago.utc
        end

        def do_partial_refresh?(source_uid)
          return false if do_full_refresh?(source_uid)

          timestamps[source_uid][:partial_refresh][:last_finished_at].nil? ||
            timestamps[source_uid][:partial_refresh][:last_finished_at] < partial_refresh_frequency.seconds.ago.utc
        end

        def full_refresh_started!(source_uid)
          refresh_started(:full_refresh, source_uid)
        end

        def full_refresh_finished!(source_uid)
          refresh_finished(:full_refresh, source_uid)
          refresh_finished(:partial_refresh, source_uid)
        end

        def partial_refresh_started!(source_uid)
          refresh_started(:partial_refresh, source_uid)
        end

        def partial_refresh_finished!(source_uid)
          refresh_finished(:partial_refresh, source_uid)
        end

        def last_partial_refresh_at(source_uid)
          return nil unless timestamps[source_uid]

          timestamps[source_uid][:partial_refresh][:last_finished_at]
        end

        private

        attr_accessor :timestamps

        def refresh_started(type, source_uid)
          add_source(source_uid) unless timestamps[source_uid]

          timestamps[source_uid][type][:started_at] = Time.now.utc
        end

        def refresh_finished(type, source_uid)
          started_at = timestamps[source_uid].try(:[], type).try(:[], :started_at)
          if started_at.nil? && type == :partial_refresh
            started_at = timestamps[source_uid].try(:[], :full_refresh).try(:[], :started_at)
          end

          raise "Refresh started_at for source #{source_uid} is missing!" if started_at.nil?

          timestamps[source_uid][type][:last_finished_at] = started_at
        end
      end
    end
  end
end
