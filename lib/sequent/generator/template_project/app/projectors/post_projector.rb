require_relative '../records/post_record'
require_relative '../../lib/post/events'

class PostProjector < Sequent::Projector
  manages_tables PostRecord

  on PostAdded do |event|
    create_record(PostRecord, aggregate_id: event.aggregate_id)
  end

  on PostAuthorChanged do |event|
    update_all_records(PostRecord, {aggregate_id: event.aggregate_id}, event.attributes.slice(:author))
  end

  on PostTitleChanged do |event|
    update_all_records(PostRecord, {aggregate_id: event.aggregate_id}, event.attributes.slice(:title))
  end

  on PostContentChanged do |event|
    update_all_records(PostRecord, {aggregate_id: event.aggregate_id}, event.attributes.slice(:content))
  end
end
