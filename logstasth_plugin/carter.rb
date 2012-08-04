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
  STATS_COLLECTION = "metrics_daily"

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
      mongo_collection.insert(
        "request_id" => event_id,
        "queue_id" => fields["request_id"].first,
        "src_hostname" => fields["src_hostname"].first,
        "src_ipaddress" => fields["src_ipaddress"].first,
        "account_id" => fields["account_id"].first,
        "running" => 1,
        "created_at" => time_to_utc(event.timestamp)
      )
      # We set the stats
      date = time_to_date(event.timestamp)
      account_id = fields["account_id"].first
      statement = {"$inc" => {"request_qty" => 1}}
      update_daily_stats(account_id, date,statement)
    end

    def update_event(event_id, event)
      # request_id can be duplicated, but only one can be running
      request = mongo_collection.find_one("request_id" => event_id, "running" => 1)
      unless request.nil?
        if event.tags.include?("queue_run")
          record_queue_run(request["_id"], event)
        elsif event.tags.include?("smtp_run")
          record_smtp_run(request["_id"], event)
        elsif event.tags.include?("queue_finish")
          record_queue_finish(request["_id"], event)
        end
      end
    end

    # We record everytime the request is put on the queue
    def record_queue_run(request_id, event)
      fields = event.fields
      mongo_collection.update({"_id" => request_id}, {"$set" => {
                                                        "src_email_address" => fields["src_email_address"].first,
                                                        "size" => fields["size"].first.to_i,
                                                        "dst_qty" => fields["dst_qty"].first.to_i,
                                                        "updated_at" => time_to_utc(event.timestamp)
      }, "$inc" => {"queue_runs" => 1}})
      # We set the stats only if the first time in queue
      if mongo_collection.find_one({"_id" => request_id}, {:fields => ["queue_runs"]})["queue_runs"] < 2
        date = time_to_date(event.timestamp)
        account_id = get_account_id_from_request(request_id)
        #TODO: Mejorar este codigo
        src_email_address = @mongodb.collection(STATS_COLLECTION).find_one({"account_id" => account_id, "date" => date, "src_emails.address" => fields["src_email_address"].first})
        if src_email_address.nil?
          statement = {"$inc" => {"request_bytes" => fields["size"].first.to_i}, "$addToSet" => {"src_emails" => {"address" => fields["src_email_address"].first}}}
        else
          statement = {"$inc" => {"request_bytes" => fields["size"].first.to_i}}
        end
        update_daily_stats(account_id, date, statement)
        @mongodb.collection(STATS_COLLECTION).update({"account_id" => account_id, "date" => date, "src_emails.address" => fields["src_email_address"].first},
                                                     {"$inc" => {"src_emails.$.count" => 1}})
      end
    end

    # We record every try to sent an email
    # The status can be = sent, deferred, bounced
    def record_smtp_run(request_id, event)
      fields = event.fields
      mongo_collection.update({"_id" => request_id}, {"$addToSet" => {
                                                        "messages" => {
                                                          "dst_email_address" => fields["dst_email_address"].first,
                                                          "dst_server_ipaddress" => fields["dst_server_ipaddress"].nil? ? "" : fields["dst_server_ipaddress"].first,
                                                          "dst_server_name" => fields["dst_server_name"].nil? ? "" : fields["dst_server_name"].first,
                                                          "dst_port" => fields["dst_port"].nil? ? "" : fields["dst_port"].first.to_i,
                                                          "status" => fields["status"].first,
                                                          "delay" => fields["delay"].first.to_i,
                                                          "response_text" => fields["response_text"].first,
                                                          "created_at" => time_to_utc(event.timestamp)
                                                        }
      }})
      # TODO
      mongo_collection.update({"_id" => request_id}, {"$inc" => {"delay" => fields["delay"].first.to_i}})
      mongo_collection.update({"_id" => request_id}, {"$addToSet" => {"dst_email_address" => fields["dst_email_address"].first}})
      mongo_collection.update({"_id" => request_id}, {"$set" => {"updated_at" => time_to_utc(event.timestamp)}, "$inc" => {"dst_sent_qty" => 1 }})

      # Update Stats
      date = time_to_date(event.timestamp)
      account_id = get_account_id_from_request(request_id)
      #TODO: Mejorar este codigo
      dst_email_address = @mongodb.collection(STATS_COLLECTION).find_one({"account_id" => account_id, "date" => date, "dst_emails.address" => fields["dst_email_address"].first})
      if dst_email_address.nil?
        statement = {"$inc" => {"sent_qty" => 1}, "$addToSet" => {"dst_emails" => {"address" => fields["dst_email_address"].first}}}
      else
        statement = {"$inc" => {"sent_qty" => 1}}
      end
      update_daily_stats(account_id, date, statement)
      @mongodb.collection(STATS_COLLECTION).update({"account_id" => account_id, "date" => date, "dst_emails.address" => fields["dst_email_address"].first},
                                                   {"$inc" => {"dst_emails.$.count" => 1}})
      unless messages_was_sent?(event)
        mongo_collection.update({"_id" => request_id}, {"$inc" => {"sent_failed_qty" => 1}})
        statement = {"$inc" => {"failed_qty" => 1}}
        update_daily_stats(account_id, date, statement)
      end
    end

    def record_queue_finish(request_id, event)
      mongo_collection.update({"_id" => request_id}, {"$set" => {
                                                        "running" => 0,
                                                        "closed_at" => time_to_utc(event.timestamp)
      }})
    end

    # Is a new event if the request_id does not exists, or if exists and is not running
    def is_new_event?(event)
      event.tags.include?("new_request")
    end

    def get_id(event)
      id = "#{event.fields['request_id'].first}_#{event.fields['logsource'].first}"
    end

  private
    def update_daily_stats(account_id, date, statement_hash)
      mongo_collection = @mongodb.collection(STATS_COLLECTION)
      mongo_collection.update({"account_id" => account_id, "date" => date}, statement_hash, {:upsert  => true})
    end

    def mongo_collection
      @mongodb.collection(@collection)
    end

    def time_to_utc(time)
      DateTime.parse(time).to_time.utc
    end

    def time_to_date(time)
      Date.parse(time).to_s
    end

    def messages_was_sent?(event)
      event.fields["status"].first == "sent"
    end

    def get_account_id_from_request(request_id)
      req = mongo_collection.find_one({"_id" => request_id}, {:fields => ["account_id"]})
      req["account_id"]
    end

end
