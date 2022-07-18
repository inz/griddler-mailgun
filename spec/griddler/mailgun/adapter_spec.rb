require 'spec_helper'

describe Griddler::Mailgun::Adapter do
  it 'registers itself with griddler' do
    expect(Griddler.adapter_registry[:mailgun]).to eq Griddler::Mailgun::Adapter
  end
end

describe Griddler::Mailgun::Adapter, '.normalize_params' do
  it 'works with Griddler::Email' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    griddler_email = Griddler::Email.new(normalized_params)
    expect(griddler_email.class).to eq Griddler::Email
  end

  it 'falls back to headers for cc' do
    params = default_params.merge(Cc: '')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:cc]).to eq ["Brandon Stark <brandon@example.com>", "Arya Stark <arya@example.com>"]
  end

  it 'passes the received array of files' do
    params = default_params.merge(
      'attachment-count' => 2,
      'attachment-1' => upload_1,
      'attachment-2' => upload_2
    )

    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:attachments]).to eq [upload_1, upload_2]
  end

  it "receives attachments sent from store action" do
    params = default_params.merge(
      "attachments" => [{ url: "sample.url", name: "sample name" },
                        { url: "sample2.url", name: "sample name 2" }]
    )
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:attachments].length).to eq 2
  end

  it 'has no attachments' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:attachments]).to be_empty
  end

  it 'gets sender from headers' do
    params = default_params.merge(From: '')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:from]).to eq "Jon Snow <jon@example.com>"
  end

  it 'falls back to sender without headers or From' do
    params = default_params.merge(From: '', 'message-headers' => '{}')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:from]).to eq "jon@example.com"
  end

  it 'gets full address from headers' do
    params = default_params.merge(To: '')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:to]).to eq ["John Doe <johndoe@example.com>", "Jane Doe <janedoe@example.com>"]
  end

  it 'handles multiple To addresses' do
    params = default_params.merge(
      To: 'Alice Cooper <alice@example.org>, John Doe <john@example.com>'
    )
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:to]).to eq [
      'Alice Cooper <alice@example.org>',
      'John Doe <john@example.com>'
    ]
  end

  it 'handles missing params' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(short_params)
    expect(normalized_params[:to]).to eq ['johndoe@example.com']
  end

  it 'handles message-headers' do
    params = default_params.merge(
      'message-headers' => '[["NotCc", "emily@example.mailgun.org"], ["Reply-To", "mail2@example.mailgun.org"]]'
    )
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    email = Griddler::Email.new(normalized_params)
    expect(email.headers["Reply-To"]).to eq "mail2@example.mailgun.org"
  end

  it 'adds Bcc when it exists' do
    params = default_params.merge('Bcc' => 'bcc@example.com')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:bcc]).to eq ['bcc@example.com']
  end

  it "adds stripped-signature as a vendor specific param" do
    params = default_params.merge(
      "stripped-signature" => "The Lannisters send their regards"
    )
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:vendor_specific][:stripped_signature]).
      to eq "The Lannisters send their regards"
  end

  it "adds stripped-text as a vendor specific param" do
    params = default_params.merge(
      "stripped-text" => "Lorem ipsum dolor sit amet."
    )
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:vendor_specific][:stripped_text]).
      to eq "Lorem ipsum dolor sit amet."
  end

  it "adds stripped-html as a vendor specific param" do
    params = default_params.merge(
      "stripped-html" => "<div>Lorem ipsum dolor sit amet.</div>"
    )
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:vendor_specific][:stripped_html]).
      to eq "<div>Lorem ipsum dolor sit amet.</div>"
  end

  it "adds recipient as a vendor specific param" do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:vendor_specific][:recipient]).to eq "johndoe@example.com"
  end

  it 'bcc is empty array when it missing' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:bcc]).to eq []
  end

  it 'accepts params with invalid encoding' do
    params = default_params.merge(subject: 'învåli∂'.encode('iso-8859-1', undef: :replace).force_encoding('utf-8'))
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:subject]).to eq 'învåli?'
  end

  def upload_1
    @upload_1 ||= ActionDispatch::Http::UploadedFile.new(
      filename: 'photo1.jpg',
      type: 'image/jpeg',
      tempfile: fixture_file('photo1.jpg')
    )
  end

  def upload_2
    @upload_2 ||= ActionDispatch::Http::UploadedFile.new(
      filename: 'photo2.jpg',
      type: 'image/jpeg',
      tempfile: fixture_file('photo2.jpg')
    )
  end

  def fixture_file(file_name)
    cwd = File.expand_path File.dirname(__FILE__)
    File.new(File.join(cwd, '../../', 'fixtures', file_name))
  end

  def json_headers
    "[
      [\"Subject\", \"multiple recipients and CCs\"],
      [\"From\", \"Jon Snow <jon@example.com>\"],
      [\"To\", \"John Doe <johndoe@example.com>, Jane Doe <janedoe@example.com>\"],
      [\"Cc\", \"Brandon Stark <brandon@example.com>, Arya Stark <arya@example.com>\"]
    ]"
  end

  def short_params
    ActiveSupport::HashWithIndifferentAccess.new(
      {
        "from" => "Jon Snow <jon@example.com>",
        "recipient" => "johndoe@example.com",
        "body-plain" => "hi"
      }
    )
  end

  def default_params
    ActiveSupport::HashWithIndifferentAccess.new(
      {
        "Cc" => "Brandon Stark <brandon@example.com>, Arya Stark <arya@example.com>",
        "From" => "Jon Snow <jon@example.com>",
        "Subject" => "multiple recipients and CCs",
        "To" => "John Doe <johndoe@example.com>, Jane Doe <janedoe@example.com>",
        "body-html" => "<div dir=\"ltr\">And attachments. Two of them. An image and a text file.</div>\r\n",
        "body-plain" => "And attachments. Two of them. An image and a text file.\r\n",
        "from" => "Jon Snow <jon@example.com>",
        "recipient" => "johndoe@example.com",
        "sender" => "jon@example.com",
        "stripped-html" => "<div dir=\"ltr\">And attachments. Two of them. An image and a text file.</div>\r\n",
        "stripped-signature" => "",
        "stripped-text" => "And attachments. Two of them. An image and a text file.",
        "subject" => "multiple recipients and CCs",
        "timestamp" => "1402113646",
        "message-headers" => json_headers
      }
    )
  end
end

describe Griddler::Mailgun::Adapter, '.normalize_params (raw MIME payload)' do
  it 'works with Griddler::Email' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    griddler_email = Griddler::Email.new(normalized_params)
    expect(griddler_email.class).to eq Griddler::Email
  end

  it 'processes attachments' do
    params = default_params do |m|
      m.add_file fixture_file('photo1.jpg').path
      m.add_file fixture_file('photo2.jpg').path
    end

    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:attachments].size).to eq 2

    expect(normalized_params[:attachments].map(&:read).map(&:size).sort).
      to eq [ fixture_file('photo1.jpg'), fixture_file('photo2.jpg') ].map(&:size).sort
  end

  it 'has no attachments' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:attachments]).to be_empty
  end

  it 'gets sender from headers' do
    params = default_params.merge(from: '')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:from]).to eq "Jon Snow <jon@example.com>"
  end

  it 'gets full address from headers' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:to]).to eq ["johndoe@example.com", "John Doe <johndoe@example.com>", "Jane Doe <janedoe@example.com>"]
  end

  it 'handles multiple To addresses' do
    params = default_params do |m|
      m.to 'Alice Cooper <alice@example.org>, John Doe <john@example.com>'
    end.merge('recipient' => '')
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:to]).to eq [
      'Alice Cooper <alice@example.org>',
      'John Doe <john@example.com>'
    ]
  end

  it 'getc cc from headers' do
    params = default_params
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:cc]).to eq ["Brandon Stark <brandon@example.com>", "Arya Stark <arya@example.com>"]
  end

  it 'adds Bcc when it exists' do
    params = default_params do |m|
      m.bcc 'bcc@example.com'
      m['bcc'].include_in_headers = true
    end
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(params)
    expect(normalized_params[:bcc]).to eq ['bcc@example.com']
  end

  it "adds recipient as a vendor specific param" do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:vendor_specific][:recipient]).to eq "johndoe@example.com"
  end

  it 'bcc is empty array when it missing' do
    normalized_params = Griddler::Mailgun::Adapter.normalize_params(default_params)
    expect(normalized_params[:bcc]).to eq []
  end

  def fixture_file(file_name)
    cwd = File.expand_path File.dirname(__FILE__)
    File.new(File.join(cwd, '../../', 'fixtures', file_name))
  end

  def default_params(&block)
    mail = Mail.new do
      from "Jon Snow <jon@example.com>"
      to "John Doe <johndoe@example.com>, Jane Doe <janedoe@example.com>"
      subject "multiple recipients and CCs"
      cc "Brandon Stark <brandon@example.com>, Arya Stark <arya@example.com>"
      text_part do
        body "And attachments. Two of them. An image and a text file.\r\n"
      end
      html_part do
        body "<div dir=\"ltr\">And attachments. Two of them. An image and a text file.</div>\r\n"
      end
      yield(self) if block_given?
    end

    ActiveSupport::HashWithIndifferentAccess.new(
      {
        "recipient" => "johndoe@example.com",
        "sender" => "jon@example.com",
        "from" => "Jon Snow <jon@example.com>",
        "subject" => "multiple recipients and CCs",
        "body-mime" => mail.to_s,
        "timestamp" => "1402113646",
      }
    )
  end
end
