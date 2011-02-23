$:.unshift File.expand_path("../../lib", __FILE__)
$:.unshift File.expand_path("../", __FILE__)
require 'ruby509.rb'
require 'test_vars.rb'
require 'rspec'


describe Ruby509::Cert do
	it "has a public_key" do
		cert = Ruby509::Cert.new @@cert
		cert.public_key.to_pem.should == @@cert_public_key
	end
	it "returns bit strength" do
		cert = Ruby509::Cert.new @@cert
		cert.bit_strength.should == 2048
	end
	it "has the right issuer" do
		cert = Ruby509::Cert.new @@cert
		cert.issuer.to_s.should == "/C=US/O=SecureTrust Corporation/CN=SecureTrust CA"
	end
	it "has the right not_before" do
		cert = Ruby509::Cert.new @@cert
		cert.not_before.to_i.should == 1282659002
	end
	it "has the right not_after" do
		cert = Ruby509::Cert.new @@cert
		cert.not_after.to_i.should == 1377267002
	end
	it "returns list of san_names when it is a san cert" do
		cert = Ruby509::Cert.new @@cert_san
		cert.san_names.should == ['langui.sh']
	end
	it "returns an empty list when it is not a san cert" do
		cert = Ruby509::Cert.new @@cert
		cert.san_names.should == nil
	end
	it "raises exception when providing invalid cert" do
		expect { Ruby509::Cert.new('invalid cert') }.to raise_error(OpenSSL::X509::CertificateError)
	end
	it "raises exception when providing invalid key" do
		expect { Ruby509::Cert.new(@@cert,'invalid key') }.to raise_error(OpenSSL::PKey::RSAError)
	end
	it "raises exception on non-matching key" do
		expect { Ruby509::Cert.new(@@cert,@@key3) }.to raise_error(ArgumentError)
	end
	it "return normal object on matching key/cert pair" do
		expect { Ruby509::Cert.new(@@cert3,@@key3) }.to_not raise_error
	end
	it "raises exception with too many params" do
		expect { Ruby509::Cert.new(@@cert3,@@key3,'thirdparam') }.to raise_error(ArgumentError)
	end
	it "writes to pem" do
		cert = Ruby509::Cert.new(@@cert)
		cert.write_pem('/tmp/cert')
		File.read('/tmp/cert').should == @@cert+"\n"
		File.delete('/tmp/cert')
	end
	it "writes to der" do
		cert = Ruby509::Cert.new(@@cert)
		cert.write_der('/tmp/cert')
		File.read('/tmp/cert').should == @@cert_der
		File.delete('/tmp/cert')
	end
	it "parses san extension" do
		cert = Ruby509::Cert.new(@@cert_san)
		cert.san_names.should == ["langui.sh"] 
	end
	context "when initialized with an OpenSSL::X509::Certificate" do
		it "returns pem on to_pem" do
			test_cert = Ruby509::Cert.new @@cert
			cert = Ruby509::Cert.new test_cert
			cert.to_pem.should == @@cert
		end
		it "returns der on to_der" do
			test_cert = Ruby509::Cert.new @@cert
			cert = Ruby509::Cert.new test_cert
			cert.to_der.should == @@cert_der
		end
		it "returns pem on to_s" do
			test_cert = Ruby509::Cert.new @@cert
			cert = Ruby509::Cert.new test_cert
			cert.to_s.should == @@cert
		end
	end
	context "when initialized with a pem" do
		it "returns on to_pem" do
			cert = Ruby509::Cert.new @@cert
			cert.to_pem.should == @@cert
		end
	#	it "returns der on to_der" do
	#		cert = Ruby509::Cert.new @@cert
	#		cert.to_der.should == @@cert_der
	#	end
	#	it "returns pem on to_s" do
	#		cert = Ruby509::Cert.new @@cert
	#		cert.to_s.should == @@cert
	#	end
	end
end
