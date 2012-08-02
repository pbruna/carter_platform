# We work with the following variables:
# queue_id: if the of the message been queuee
# 

require "logstash/outputs/base"
require "logstash/namespace"
require "date"

class LogStash::Outputs::Carter < LogStash::Outputs::Base

  config_name "carter"
  plugin_status "beta"
  TAGS = %w( new_request queue_run smtp_run queue_finish )

  # your mongodb host
  config :host, :validate => :string, :required => true

  # the mongodb port
  config :port, :validate => :number, :default => 27017

  # The database to use
  config :database, :validate => :string, :required => true

  config :user, :validate => :string, :required => false
  config :password, :validate => :password, :required => false

  # The collection to use. This value can use %{foo} values to dynamically
  # select a collection based on data in the event.
  config :collection, :validate => :string, :required => true

  public
    def register
      require "mongo"
      # TODO(petef): check for errors
      db = Mongo::Connection.new(@host, @port).db(@database)
      auth = true
      if @user then
        auth = db.authenticate(@user, @password.value) if @user
      end
      if not auth then
        raise RuntimeError, "MongoDB authentication failure"
      end
      @mongodb = db
    end # def register

  public
    def receive(event)
      return unless output?(event)
      return unless (event.tags & TAGS).size > 0
      record event
      #@mongodb.collection(event.sprintf(@collection)).insert(event.to_hash)
    end
    
    def record(event)
      event_id = get_id(event)
      if is_new_event?(event)
        create_event(event_id, event)
      else
        update_event(event_id, event)
      end
    end
    
    def create_event(event_id, event)
      fields = event.fields
      @mongodb.collection(mongo_collection).insert(
        "request_id" => event_id,
        "queue_id" => fields["request_id"].first,
        "src_hostname" => fields["src_hostname"].first,
        "src_ipaddress" => fields["src_ipaddress"].first,
        "account_id" => fields["account_id"].first,
        "running" => 1,
        "created_at" => DateTime.parse(event.timestamp).to_time.utc
      )
    end
    
    def update_event(event_id, event)
      request = @mongodb.collection(mongo_collection).find_one("request_id" => event_id, "running" => 1)
      if event.tags.include?("queue_run")
        record_queue_run(request, event)
      elsif event.tags.include?("smtp_run")
        record_smtp_run(request, event)
      elsif event.tags.include?("queue_finish")
        record_queue_finish(request, event)
      end
    end
    
    def record_queue_run(request, event)
      fields = event.fields
      @mongodb.collection(mongo_collection).update({"request_id" => request["request_id"]}, {"$set" => {
        "src_email_address" => fields["src_email_address"].first,
        "size" => fields["size"].first.to_i,
        "dst_qty" => fields["dst_qty"].first.to_i,
        "updated_at" => DateTime.parse(event.timestamp).to_time.utc
      }, "$inc" => {"queue_runs" => 1}})
    end
    
    def record_smtp_run(request, event)
      
    end
    
    def record_queue_finish(request, event)
      
    end
    
    # Is a new event if the request_id does not exists, or if exists and is not running
    def is_new_event?(event)
      return false unless event.tags.include?("new_request")
      event_id = get_id(event)
      result = @mongodb.collection(mongo_collection).find("request_id" => event_id).to_a
      if result.size < 1
        return true
      else
        result = @mongodb.collection(mongo_collection).find("request_id" => event_id, "running" => 0).to_a
        result.size < 1
      end
    end
    
    def get_id(event) 
      id = "#{event.fields['request_id'].first}_#{event.fields['logsource'].first}"
    end
  
  private
  def mongo_collection
    @collection
  end
    
end
