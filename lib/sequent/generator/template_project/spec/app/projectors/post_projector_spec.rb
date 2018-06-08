require_relative '../../spec_helper'
require_relative '../../../app/projectors/post_projector'

describe PostProjector do
  let(:aggregate_id) { Sequent.new_uuid }
  let(:post_projector) { PostProjector.new }
  let(:post_added) { PostAdded.new(aggregate_id: aggregate_id, sequence_number: 1) }

  context PostAdded do
    it 'creates a projection' do
      post_projector.handle_message(post_added)
      expect(PostRecord.count).to eq(1)
      record = PostRecord.first
      expect(record.aggregate_id).to eq(aggregate_id)
    end
  end

  context PostTitleChanged do
    let(:post_title_changed) do
      PostTitleChanged.new(aggregate_id: aggregate_id, title: 'ben en kim', sequence_number: 2)
    end

    before { post_projector.handle_message(post_added) }

    it 'updates a projection' do
      post_projector.handle_message(post_title_changed)
      expect(PostRecord.count).to eq(1)
      record = PostRecord.first
      expect(record.title).to eq('ben en kim')
    end
  end
end
