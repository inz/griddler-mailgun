require 'tempfile'

module Griddler
  module Mailgun
    class Adapter
      attr_reader :params

      def initialize(params)
        @params = deep_clean_invalid_utf8_bytes(params)
      end

      def self.normalize_params(params)
        adapter = new(params)
        adapter.normalize_params
      end

      def normalize_params
        normalize_params_from_mime_message || normalize_params_from_request
      end

    private

      def deep_clean_invalid_utf8_bytes(object)
        case object
        when Hash, ->(o) { o.respond_to?(:transform_values) }
          object.transform_values { |v| deep_clean_invalid_utf8_bytes(v) }
        when Array
          object.map { |element| deep_clean_invalid_utf8_bytes(element) }
        when String
          clean_invalid_utf8_bytes(object)
        else
          object
        end
      end

      def clean_invalid_utf8_bytes(text)
        if text && !text.valid_encoding?
          text.force_encoding('ISO-8859-1').encode('UTF-8')
        else
          text
        end
      end

      def normalize_params_from_mime_message
        return nil unless mime_message

        {
          to: to_recipients_from_mime_message,
          cc: formatted_field_from_mime_message('cc'),
          bcc: formatted_field_from_mime_message('bcc'),
          from: formatted_field_from_mime_message('from').first || determine_sender,
          subject: mime_message.subject,
          text: mime_message.text_part&.body&.to_s || mime_message.body.to_s,
          html: mime_message.html_part&.body&.to_s&.presence,
          attachments: attachment_files_from_mime_message,
          headers: mime_message.header.to_s,
          vendor_specific: {
            recipient: params['recipient']
          }
        }
      end

      def normalize_params_from_request
        {
          to: to_recipients,
          cc: cc_recipients,
          bcc: Array.wrap(param_or_header(:Bcc)),
          from: determine_sender,
          subject: params[:subject],
          text: params['body-plain'],
          html: params['body-html'],
          attachments: attachment_files,
          headers: serialized_headers,
          vendor_specific: {
            stripped_text: params['stripped-text'],
            stripped_signature: params['stripped-signature'],
            stripped_html: params['stripped-html'],
            recipient: params['recipient']
          }
        }
      end

      def determine_sender
        sender = param_or_header(:From)
        sender ||= params[:sender]
      end

      def to_recipients
        to_emails = param_or_header(:To)
        to_emails ||= params[:recipient]
        to_emails.split(',').map(&:strip)
      end

      def cc_recipients
        cc = param_or_header(:Cc) || ''
        cc.split(',').map(&:strip)
      end

      def headers
        @headers ||= extract_headers
      end

      def extract_headers
        extracted_headers = {}
        if params['message-headers']
          parsed_headers = JSON.parse(params['message-headers'])
          parsed_headers.each{ |h| extracted_headers[h[0]] = h[1] }
        end
        ActiveSupport::HashWithIndifferentAccess.new(extracted_headers)
      end

      def serialized_headers

        # Griddler expects unparsed headers to pass to ActionMailer, which will manually
        # unfold, split on line-endings, and parse into individual fields.
        #
        # Mailgun already provides fully-parsed headers in JSON -- so we're reconstructing
        # fake headers here for now, until we can find a better way to pass the parsed
        # headers directly to Griddler

        headers.to_a.collect { |header| "#{header[0]}: #{header[1]}" }.join("\n")
      end

      def param_or_header(key)
        if params[key].present?
          params[key]
        elsif headers[key].present?
          headers[key]
        else
          nil
        end
      end

      def attachment_files
        if params["attachment-count"].present?
          attachment_count = params["attachment-count"].to_i

          attachment_count.times.map do |index|
            params.delete("attachment-#{index+1}")
          end
        else
          params["attachments"] || []
        end
      end

      def mime_message
        return nil unless params['body-mime'].present?
        @mime_message ||= Mail.new(params['body-mime'])
      end

      def formatted_field_from_mime_message(field_name)
        mime_message[field_name].then do |f|
          f.respond_to?(:formatted) ? f.formatted : Array(f&.to_s)
        end
      end

      def to_recipients_from_mime_message
        Array(params['recipient'].presence) + formatted_field_from_mime_message('to')
      end

      def attachment_files_from_mime_message
        mime_message.attachments&.map do |attachment|
          ActionDispatch::Http::UploadedFile.new(
            filename: attachment.filename.presence || 'untitled',
            type: attachment.content_type&.split(';')&.first,
            tempfile: Tempfile.new.tap(&:binmode).tap(&:unlink).
              tap { |f| f.write attachment.decoded }.tap(&:rewind)
          )
        end
      end
    end
  end
end
