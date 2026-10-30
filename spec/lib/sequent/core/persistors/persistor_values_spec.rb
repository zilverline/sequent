# frozen_string_literal: true

require 'spec_helper'

class PersistorValuesRecord < Sequent::ApplicationRecord; end

class PersistorTypesRecord < Sequent::ApplicationRecord
  enum :status, {draft: 0, sent: 1}
end

class PersistorNormalizedTypesRecord < PersistorTypesRecord
  normalizes :label, with: ->(label) { label || 'none' }, apply_to_nil: true
end

# The persistors store the same values, cast like ActiveRecord casts them.
describe 'Persistors storing values' do
  before do
    exec_sql(<<~SQL)
      DROP TABLE IF EXISTS persistor_values_records;
      CREATE TABLE persistor_values_records (
        name character varying,
        initials character varying[] DEFAULT '{}',
        created_at timestamp without time zone,
        updated_at timestamp without time zone
      );
      DROP TABLE IF EXISTS persistor_types_records;
      CREATE TABLE persistor_types_records (
        id bigserial PRIMARY KEY,
        number integer,
        amount numeric(12, 2),
        day date,
        at timestamp without time zone,
        at_tz timestamp with time zone,
        flag boolean,
        label character varying,
        identifier uuid,
        tags character varying[],
        data jsonb,
        status integer
      );
    SQL
    [PersistorValuesRecord, PersistorTypesRecord, PersistorNormalizedTypesRecord].each(&:reset_column_information)
  end

  shared_examples 'a persistor storing values' do |except: []|
    context 'of all column types' do
      let(:record_class) { PersistorTypesRecord }
      let(:uuid) { Sequent.new_uuid }
      let(:columns) do
        %i[number amount day at flag label identifier tags data status]
      end

      def stored(values)
        persistor.create_record(record_class, values)
        persistor.commit
        record_class.pluck(*columns).sole
      end

      it 'stores values that have the type of their column' do
        expect(
          stored(
            number: 3,
            amount: BigDecimal('1.255'),
            day: Date.new(2026, 1, 2),
            at: Time.utc(2026, 1, 2, 3, 4, 5, 123_456),
            flag: true,
            label: "tab\t, backslash \\, newline \n and quote \"",
            identifier: uuid,
            tags: %w[a b],
            data: {'k' => 1},
            status: 'sent',
          ),
        ).to eq [
          3,
          BigDecimal('1.26'),
          Date.new(2026, 1, 2),
          Time.utc(2026, 1, 2, 3, 4, 5, 123_456),
          true,
          "tab\t, backslash \\, newline \n and quote \"",
          uuid,
          %w[a b],
          {'k' => 1},
          'sent',
        ]
      end

      it 'stores values of other types like ActiveRecord' do
        expect(
          stored(
            number: '4',
            amount: 2.5,
            day: '2026-01-03',
            at: Time.utc(2026, 1, 2, 3, 4, 5, 123_456.789r),
            flag: 'false',
            label: :symbol,
            identifier: uuid.upcase,
            tags: [:a, 1],
            data: {k: BigDecimal('1.5')},
            status: 1,
          ),
        ).to eq [
          4,
          BigDecimal('2.5'),
          Date.new(2026, 1, 3),
          Time.utc(2026, 1, 2, 3, 4, 5, 123_456),
          false,
          'symbol',
          uuid,
          %w[a 1],
          {'k' => '1.5'},
          'sent',
        ]
      end

      it 'stores times in other time zones in UTC' do
        expect(stored(at: Time.new(2026, 1, 2, 4, 4, 5, '+01:00')).fetch(3)).to eq Time.utc(2026, 1, 2, 3, 4, 5)
        record_class.delete_all
        expect(stored(at: DateTime.new(2026, 1, 2, 4, 4, 5, '+01:00')).fetch(3)).to eq Time.utc(2026, 1, 2, 3, 4, 5)
      end

      context 'with times in Europe/Amsterdam' do
        let(:amsterdam) { TZInfo::Timezone.get('Europe/Amsterdam') }

        def stored_text(column, values)
          persistor.create_record(record_class, values)
          persistor.commit
          Sequent::ApplicationRecord.connection.select_value(
            "SELECT #{column}::text FROM persistor_types_records",
          )
        ensure
          record_class.delete_all
        end

        def with_process_time_zone(time_zone)
          previous = ENV.fetch('TZ', nil)
          ENV['TZ'] = time_zone
          yield
        ensure
          ENV['TZ'] = previous
        end

        it 'stores times of Time.zone in UTC' do
          Time.use_zone('Europe/Amsterdam') do
            expect(stored_text(:at, at: Time.zone.local(2026, 7, 1, 12))).to eq '2026-07-01 10:00:00'
            expect(stored_text(:at, at: Time.zone.local(2026, 1, 1, 12))).to eq '2026-01-01 11:00:00'
          end
        end

        it 'stores times with a time zone object in UTC' do
          expect(stored_text(:at, at: Time.new(2026, 7, 1, 12, in: amsterdam))).to eq '2026-07-01 10:00:00'
          expect(stored_text(:at, at: Time.new(2026, 1, 1, 12, in: amsterdam))).to eq '2026-01-01 11:00:00'
        end

        it 'stores local times of the process time zone in UTC' do
          with_process_time_zone('Europe/Amsterdam') do
            expect(stored_text(:at, at: Time.new(2026, 7, 1, 12))).to eq '2026-07-01 10:00:00'
            expect(stored_text(:at, at: Time.new(2026, 1, 1, 12))).to eq '2026-01-01 11:00:00'
          end
        end

        it 'stores times in a timestamp with time zone column' do
          at_tz_in_utc = "(at_tz AT TIME ZONE 'UTC')"

          expect(stored_text(at_tz_in_utc, at_tz: Time.utc(2026, 7, 1, 10))).to eq '2026-07-01 10:00:00'
          expect(stored_text(at_tz_in_utc, at_tz: Time.new(2026, 7, 1, 12, in: amsterdam)))
            .to eq '2026-07-01 10:00:00'
          expect(stored_text(at_tz_in_utc, at_tz: DateTime.new(2026, 1, 1, 12, 0, 0, '+01:00')))
            .to eq '2026-01-01 11:00:00'
          Time.use_zone('Europe/Amsterdam') do
            expect(stored_text(at_tz_in_utc, at_tz: Time.zone.local(2026, 7, 1, 12))).to eq '2026-07-01 10:00:00'
            expect(stored_text(at_tz_in_utc, at_tz: Time.zone.local(2026, 1, 1, 12))).to eq '2026-01-01 11:00:00'
          end
          with_process_time_zone('Europe/Amsterdam') do
            expect(stored_text(at_tz_in_utc, at_tz: Time.new(2026, 1, 1, 12))).to eq '2026-01-01 11:00:00'
          end
        end

        it 'stores the date of a time in a date column' do
          Time.use_zone('Europe/Amsterdam') do
            expect(stored_text(:day, day: Time.zone.local(2026, 7, 1, 0, 30))).to eq '2026-07-01'
          end
          with_process_time_zone('Europe/Amsterdam') do
            expect(stored_text(:day, day: Time.new(2026, 7, 1, 0, 30))).to eq '2026-07-01'
          end
        end

        context 'when ActiveRecord stores local times' do
          around do |example|
            with_process_time_zone('Europe/Amsterdam') do
              previous = ActiveRecord.default_timezone
              ActiveRecord.default_timezone = :local
              example.run
            ensure
              ActiveRecord.default_timezone = previous
            end
          end

          def stored_by_active_record(column, values)
            record_class.create!(values)
            Sequent::ApplicationRecord.connection.select_value(
              "SELECT #{column}::text FROM persistor_types_records",
            )
          ensure
            record_class.delete_all
          end

          it 'stores times in a timestamp with time zone column like ActiveRecord does' do
            at_tz_in_utc = "(at_tz AT TIME ZONE 'UTC')"
            [Time.utc(2026, 7, 1, 10), Time.new(2026, 1, 1, 12), Time.new(2026, 7, 1, 12, in: amsterdam)].each do |time|
              expect(stored_text(at_tz_in_utc, at_tz: time)).to eq stored_by_active_record(at_tz_in_utc, at_tz: time)
            end
          end

          it 'stores times in the local time zone' do
            expect(stored_text(:at, at: Time.utc(2026, 7, 1, 10))).to eq '2026-07-01 12:00:00'
            expect(stored_text(:at, at: Time.utc(2026, 1, 1, 11))).to eq '2026-01-01 12:00:00'
            expect(stored_text(:at, at: Time.new(2026, 7, 1, 12))).to eq '2026-07-01 12:00:00'
            Time.use_zone('Europe/Amsterdam') do
              expect(stored_text(:at, at: Time.zone.local(2026, 1, 1, 12))).to eq '2026-01-01 12:00:00'
            end
          end
        end
      end

      it 'stores NULL for nil and for values that cannot be cast' do
        expect(stored(number: nil, identifier: 'not a uuid', label: nil, tags: nil, data: nil))
          .to eq [nil] * columns.size
      end

      it 'rounds decimals to the scale of their column like ActiveRecord' do
        BigDecimal.save_rounding_mode do
          BigDecimal.mode(BigDecimal::ROUND_MODE, :banker)

          expect(stored(amount: BigDecimal('1.125')).fetch(1)).to eq BigDecimal('1.12')
        end
      end

      context 'with a column normalized when nil' do
        let(:record_class) { PersistorNormalizedTypesRecord }

        it 'stores the normalized value of nil' do
          expect(stored(label: nil).fetch(5)).to eq 'none'
        end

        unless except.include?(:normalized_without_value)
          it 'stores the normalized value of nil for a column without a value' do
            expect(stored(number: 1).fetch(5)).to eq 'none'
          end
        end
      end
    end

    context 'of records' do
      let(:created_at) { Time.utc(2026, 1, 2, 3, 4, 5) }

      it 'quotes the table and column names' do
        Sequent::ApplicationRecord.connection.execute(
          'ALTER TABLE persistor_values_records ADD COLUMN "order" integer',
        )
        PersistorValuesRecord.reset_column_information

        persistor.create_record(PersistorValuesRecord, {name: 'ben', order: 1, created_at:})
        persistor.commit

        expect(PersistorValuesRecord.pluck(:name, :order)).to eq [['ben', 1]]
      ensure
        PersistorValuesRecord.reset_column_information
      end

      it 'stores all values of all records' do
        persistor.create_records(
          PersistorValuesRecord,
          [
            {name: 'bén, "quoted"', initials: %w[b j], created_at:},
            {name: nil, initials: [], created_at:},
          ],
        )
        persistor.commit

        expect(PersistorValuesRecord.order(:name).pluck(:name, :initials, :created_at)).to eq [
          ['bén, "quoted"', %w[b j], created_at],
          [nil, [], created_at],
        ]
      end

      it 'stores created_at as updated_at' do
        persistor.create_record(PersistorValuesRecord, {name: 'a', created_at:})
        persistor.create_records(PersistorValuesRecord, [{name: 'b', created_at:}])
        persistor.create_or_update_record(PersistorValuesRecord, {name: 'c'}, created_at) { |_| }
        persistor.commit

        expect(PersistorValuesRecord.order(:name).pluck(:created_at, :updated_at)).to eq [[created_at, created_at]] * 3
      end

      it 'stores a given updated_at' do
        updated_at = created_at + 1
        persistor.create_record(PersistorValuesRecord, {name: 'a', created_at:, updated_at:})
        persistor.create_records(PersistorValuesRecord, [{name: 'b', created_at:, updated_at:}])
        persistor.commit

        expect(PersistorValuesRecord.pluck(:updated_at)).to eq [updated_at, updated_at]
      end

      it 'stores the current time as the timestamps without created_at, like ActiveRecord' do
        persistor.create_record(PersistorValuesRecord, {name: 'a'})
        persistor.create_records(PersistorValuesRecord, [{name: 'b'}])
        persistor.commit

        expect(PersistorValuesRecord.pluck(:created_at, :updated_at).flatten).to all(be_within(1.minute).of(Time.now))
      end

      it 'stores the records in the current transaction' do
        Sequent::ApplicationRecord.transaction do
          persistor.create_record(PersistorValuesRecord, {name: 'ben', created_at:})
          persistor.commit
          fail ActiveRecord::Rollback
        end

        expect(PersistorValuesRecord.count).to eq 0
      end
    end
  end

  context Sequent::Core::Persistors::ActiveRecordPersistor do
    let(:persistor) { Sequent::Core::Persistors::ActiveRecordPersistor.new }

    it_behaves_like 'a persistor storing values', except: %i[normalized_without_value]

    it 'stores records with and without created_at using create_records without record timestamps' do
      PersistorValuesRecord.record_timestamps = false
      created_at = Time.utc(2026, 1, 2)
      persistor.create_records(PersistorValuesRecord, [{name: 'a', created_at: nil}, {name: 'b', created_at:}])

      expect(PersistorValuesRecord.order(:name).pluck(:created_at)).to eq [nil, created_at]
    ensure
      PersistorValuesRecord.record_timestamps = true
    end

    # ActiveRecord only normalizes the values assigned to a record.
    it 'stores NULL for a column normalized when nil without a value' do
      persistor.create_record(PersistorNormalizedTypesRecord, number: 1)

      expect(PersistorNormalizedTypesRecord.pluck(:label)).to eq [nil]
    end
  end

  context Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor do
    let(:persistor) { Sequent::Core::Persistors::ReplayOptimizedPostgresPersistor.new }

    it_behaves_like 'a persistor storing values'
  end
end
