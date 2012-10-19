# We work with the following variables:
# queue_id: if the of the message been queuee
#

require "logstash/outputs/base"
require "logstash/namespace"
require "date"

class LogStash::Outputs::Carter < LogStash::Outputs::Base

  # only process loglines with any of these tags
  TAGS = %w( new_request queue_run smtp_run queue_finish message_id amavis_run noqueue_run)

  # collection on mongo where to store de kpi
  STATS_COLLECTION = "metrics_daily"

  # reject this key value pair in logline
  REJECT_KEYS = %( facility facility_label message pid priority program severity severity_label)

  # plugin name
  config_name "carter"

  # plugin stauts
  plugin_status "beta"

  # account name to store the information
  config :account_id, :validate => :string, :required => false

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
      auth = db.authenticate(@user, @password.value) if @user
      raise RuntimeError, "MongoDB authentication failure" unless auth
      @mongodb = db
    end

  public
    def receive(event)
      return unless output?(event)
      return unless (event.tags & TAGS).size > 0

      #get the account_id from the source ip address
      @account_id ||= get_account_id(event.source_host)
      record event
    end

    def record(event)
      event_id = get_event_id(event)
      return create_event(event_id, event) if is_new_event?(event)
      update_event(event_id, event)
    end

    def create_event(event_id, event)
      fields = get_event_fields(event)
      fields.merge!({"running" => 1,
                     "created_at" => time_to_utc(fields["timestamp"]),
                     "request_id" => event_id,
                     "account_id" => @account_id })

      # We set the stats
      date = time_to_date(fields["timestamp"])
      statment = {"$inc" => {"request_qty" => 1}}

      if event.tags.include?("noqueue_run")
        fields["queue_id"] = "NOQUEUE"
        fields["running"] = 0
        fields["dst_email_address"] = [fields["dst_email_address"]]
        fields["closed_at"] = time_to_utc(fields["timestamp"])
        statment = {"$inc" => {"request_qty" => 1, "sent_failed_qty" => 1}}
      end

      mongo_collection.insert(fields)
      update_daily_stats(@account_id, date, statment)
    end

    def update_event(event_id, event)
      if event.tags.include?("amavis_run")
        record_amavis_run(event)
      else
        # request_id can be duplicated, but only one can be running
        request_id = mongo_collection.find_one({"request_id" => event_id, "running" => 1}, {:fields => ["_id"]})["_id"]
        return if request_id.nil?

        record_queue_run(request_id, event) if event.tags.include?("queue_run")
        record_message_id(request_id, event) if event.tags.include?("message_id")
        record_smtp_run(request_id, event) if event.tags.include?("smtp_run")
        record_queue_finish(request_id, event) if event.tags.include?("queue_finish")
      end
    end

    # We record everytime the request is put on the queue
    def record_queue_run(request_id, event)
      fields = get_event_fields(event)
      fields.merge!( {"updated_at" => time_to_utc(fields["timestamp"]) } )
      mongo_collection.update({"_id" => request_id}, {"$set" => fields, "$inc" => {"queue_runs" => 1}})

      # We set the stats only if the first time in queue
      # this is because we are adding emails address and it does make not sense
      # to add the address more than one for the same message
      return unless first_queue_run?(request_id)
      date = time_to_date(fields["timestamp"])
      account_id = @account_id
      statment = {"$inc" => {"request_bytes" => fields["size"]}}

      # We add the email address if is not already on the daily stats
      unless email_exists_on_stats?(account_id, date, fields["src_email_address"], "src")
        statment.merge!({"$addToSet" => {"src_emails" => {"address" => fields["src_email_address"]}}})
      end

      update_daily_stats(account_id, date, statment)
      @mongodb.collection(STATS_COLLECTION).update({"account_id" => account_id, "date" => date, "src_emails.address" => fields["src_email_address"]},
                                                   {"$inc" => {"src_emails.$.count" => 1}})
    end

    def record_message_id(request_id, event)
      fields = get_event_fields(event)
      request = mongo_collection.find_one({"message_id" => fields["message_id"]}, {:fields => ["_id", "message_id", "request_id"] })
      if request.nil?
        mongo_collection.update({"_id" => request_id}, {"$set" => fields} )
      else
        # We remove the new request comming from amavis
        # and add the request_id to the original request
        mongo_collection.remove({"request_id" => get_event_id(event)})
        mongo_collection.update({"_id" => request["_id"]}, {"$set" => {"running" => 1, "request_id" => [request["request_id"], get_event_id(event)].flatten }})
      end
    end

    # We record every try to sent an email
    # The status can be = sent, deferred, bounced
    def record_smtp_run(request_id, event)
      fields = get_event_fields(event)
      fields.merge!({"created_at" => time_to_utc(fields["timestamp"])})
      mongo_collection.update({"_id" => request_id}, {"$addToSet" => { "messages" => fields }})

      # TODO
      mongo_collection.update({"_id" => request_id}, {"$inc" => { "delay" => fields["delay"], "dst_sent_qty" => 1 },
                                                      "$addToSet" => { "dst_email_address" => fields["dst_email_address"] },
                                                      "$set" => { "updated_at" => time_to_utc(event.timestamp) }
                                                      })

      # Update Stats
      date = time_to_date(fields["timestamp"])
      account_id = @account_id
      statment = {"$inc" => {"sent_qty" => 1}}

      # We add the email address if is not already on the daily stats
      unless email_exists_on_stats?(account_id, date, fields["dst_email_address"], "dst")
        statment.merge!({"$addToSet" => {"dst_emails" => {"address" => fields["dst_email_address"]}}})
      end

      update_daily_stats(account_id, date, statment)
      @mongodb.collection(STATS_COLLECTION).update({"account_id" => account_id, "date" => date,
                                                    "dst_emails.address" => fields["dst_email_address"]},
                                                   {"$inc" => {"dst_emails.$.count" => 1}}
                                                   )

      unless messages_was_sent?(event)
        mongo_collection.update({"_id" => request_id}, {"$inc" => {"sent_failed_qty" => 1}})
        statment = {"$inc" => {"failed_qty" => 1}}
        update_daily_stats(account_id, date, statment)
      end
    end

    def record_queue_finish(request_id, event)
      fields = get_event_fields(event)
      mongo_collection.update({"_id" => request_id}, {"$set" => {"closed_at" => time_to_utc(fields["timestamp"])},
                                                      "$inc" => { "remove" => 1 }
                                                      })

      request = mongo_collection.find_one({ "_id" => request_id }, { :fields => ["request_id", "remove"] })
      if [request["request_id"]].flatten.size == request["remove"]
        mongo_collection.update({"_id" => request_id}, {"$set" => { "running" => 0 }, "$unset" => { "remove" => 1 }})
      end
    end

    def record_amavis_run(event)
      message_id = event["message_id"].first
      fields = get_event_fields(event)
      fields.delete("message_id")
      mongo_collection.update({ "message_id" => message_id },
                              { "$set" => { "amavis_data" => fields }},
                              {:upsert => true})

      # update the blocked_qty in daily_stats if the emails is spam
      unless fields["amavis_status"].downcase == "passed"
        date = time_to_date(fields["timestamp"])
        account_id = @account_id
        statment = {"$inc" => {"blocked_qty" => 1}}
        update_daily_stats(account_id, date, statment)
      end

    end

    def is_new_event?(event)
      event.tags.include?("new_request") || event.tags.include?("noqueue_run")
    end

    def get_event_id(event)
      return "NOQUEUE_#{event.source_host}" if event.fields["queue_id"].nil?
      request_id = event.fields["queue_id"].class == Array ? event.fields["queue_id"].first : event.fields["queue_id"]
      "#{request_id}_#{event.source_host}"
    end

  private
    def email_exists_on_stats?(account_id, date, email, array_name)
      email_address = @mongodb.collection(STATS_COLLECTION).find_one({"account_id" => account_id, "date" => date, "#{array_name}_emails.address" => email})
      !email_address.nil?
    end

    def first_queue_run?(request_id)
      mongo_collection.find_one({"_id" => request_id}, {:fields => ["queue_runs"]})["queue_runs"] == 1
    end

    def get_event_fields(event)
      fields = event.fields
      fields.delete_if {|k,v| REJECT_KEYS.include?(k) }
      fields.each do |k,v|
        value = v.respond_to?(:first) ? v.first : "#{v}"
        value = value.to_f if value.match(/^[+-]?(?:(?!0)\d+|0)(?:\.\d+)?$/)
        fields[k] = value
      end
      fields
    end

    def update_daily_stats(account_id, date, statment_hash)
      mongo_collection = @mongodb.collection(STATS_COLLECTION)
      mongo_collection.update({"account_id" => account_id, "date" => date}, statment_hash, {:upsert  => true})
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
      event.fields["status"] == "sent"
    end

    def get_account_id(src_ipaddress)
      @mongodb.collection("accounts").find_one({:ipaddress => src_ipaddress}, {:fields => ["_id"]})["_id"]
    end

end
