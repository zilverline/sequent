require 'spec_helper'
require 'sequent/test/time_comparison'

class ActiveSupport::TimeWithZone
  def self.parse(str)
    Time.zone.parse(str)
  end
end

describe 'Time comparison' do
  around do |example|
    original_time_zone = Time.zone
    Time.zone = 'UTC'
    example.run
  ensure
    Time.zone = original_time_zone
  end

  time_classes = [Time, DateTime, ActiveSupport::TimeWithZone]
  options = time_classes.product(time_classes)

  nano = '2015-08-14T15:17:23.123456789+00:00'
  micro = '2015-08-14T15:17:23.123456+00:00'

  time_options = [nano, micro].product([nano, micro])

  options.each do |some_class, other_class|
    time_options.each do |some_time, other_time|
      context "given a #{some_class} (#{some_time})" do
        context "and a #{other_class} (#{other_time})" do
          it 'is equal' do
            expect(some_class.parse(some_time)).to eq(other_class.parse(other_time))
          end
        end
      end
    end
  end

  context 'when other is nil' do
    it 'is not equal' do
      expect(Time.now == nil).to be_falsey
      expect(DateTime.now == nil).to be_falsey
      expect(Time.current == nil).to be_falsey
    end
  end

  context 'when other is not time related' do
    it 'is not equal' do
      expect(Time.now == :test).to be_falsey
      expect(DateTime.now == :test).to be_falsey
      expect(Time.current == :test).to be_falsey
    end
  end

end
