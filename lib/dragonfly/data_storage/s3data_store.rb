require 'fog'

module Dragonfly
  module DataStorage

    class S3DataStore

      include Configurable
      include Serializer

      configurable_attr :bucket_name
      configurable_attr :access_key_id
      configurable_attr :secret_access_key
      configurable_attr :use_filesystem, true
      configurable_attr :region
      configurable_attr :storage_headers, {'x-amz-acl' => 'public-read'}

      REGIONS = {
        'us-east-1'      => 's3.amazonaws.com',  #default
        'eu-west-1'      => 's3-eu-west-1.amazonaws.com',
        'ap-southeast-1' => 's3-ap-southeast-1.amazonaws.com',
        'us-west-1'      => 's3-us-west-1.amazonaws.com'
      }

      def initialize(opts={})
        self.bucket_name = opts[:bucket_name]
        self.access_key_id = opts[:access_key_id]
        self.secret_access_key = opts[:secret_access_key]
        self.region = opts[:region]
      end

      def store(temp_object, opts={})
        ensure_initialized
        meta = opts[:meta] || {}
        uid = opts[:path] || generate_uid(meta[:name] || temp_object.original_filename || 'file')
        if use_filesystem
          temp_object.file do |f|
            storage.put_object(bucket_name, uid, f, full_storage_headers(meta))
          end
        else
          storage.put_object(bucket_name, uid, temp_object.data, full_storage_headers(meta))
        end
        uid
      end

      def retrieve(uid)
        response = storage.get_object(bucket_name, uid)
        [
          response.body,
          parse_s3_metadata(response.headers)
        ]
      rescue Excon::Errors::NotFound => e
        raise DataNotFound, "#{e} - #{uid}"
      end

      def destroy(uid)
        storage.delete_object(bucket_name, uid)
      end

      def domain
        REGIONS[get_region]
      end

      private

      def storage
        @storage ||= Fog::Storage.new(
          :provider => 'AWS',
          :aws_access_key_id => access_key_id,
          :aws_secret_access_key => secret_access_key,
          :region => region
        )
      end

      def ensure_initialized
        unless @initialized
          ensure_bucket_exists
          @initialized = true
        end
      end

      def ensure_bucket_exists
        storage.put_bucket(bucket_name, 'LocationConstraint' => region) unless bucket_exists?
      end

      def get_region
        reg = region || 'us-east-1'
        raise "Invalid region #{reg} - should be one of #{valid_regions.join(', ')}" unless valid_regions.include?(reg)
        reg
      end

      def bucket_exists?
        storage.get_bucket_location(bucket_name)
        true
      rescue Excon::Errors::NotFound => e
        false
      end

      def generate_uid(name)
        "#{Time.now.strftime '%Y/%m/%d/%H/%M/%S'}/#{rand(1000)}/#{name.gsub(/[^\w.]+/, '_')}"
      end

      def full_storage_headers(meta)
        {'x-amz-meta-extra' => marshal_encode(meta)}.merge(storage_headers)
      end

      def parse_s3_metadata(headers)
        encoded_meta = headers['x-amz-meta-extra']
        (marshal_decode(encoded_meta) if encoded_meta) || {}
      end

      def valid_regions
        REGIONS.keys
      end

    end

  end
end
