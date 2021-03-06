require 'spec_helper'

describe R509::CertificateAuthority::Signer do
  before :each do
    @csr = TestFixtures::CSR
    @csr_invalid_signature = TestFixtures::CSR_INVALID_SIGNATURE
    @csr3 = TestFixtures::CSR3
    @test_ca_config = TestFixtures.test_ca_config
    @ca = R509::CertificateAuthority::Signer.new(@test_ca_config)
    @ca_no_profile = R509::CertificateAuthority::Signer.new(TestFixtures.test_ca_no_profile_config)
    @spki = TestFixtures::SPKI
  end

  it "raises an error if you don't pass csr or spki" do
    expect { @ca.sign({ :profile_name => 'server' }) }.to raise_error(ArgumentError, "You must supply either :csr or :spki")
  end
  it "raises an error if you pass a config that has no private key for ca_cert" do
    config = R509::Config::CAConfig.new( :ca_cert => R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT) )
    profile = R509::Config::CAProfile.new
    config.set_profile("some_profile",profile)
    expect { R509::CertificateAuthority::Signer.new(config) }.to raise_error(R509::R509Error, "You must have a private key associated with your CA certificate to issue")
  end
  it "raises an error if you pass both csr and spki" do
    csr = R509::CSR.new(:csr => @csr)
    spki = R509::SPKI.new(:spki => @spki, :subject=>[['CN','test']])
    expect { @ca.sign({ :spki => spki, :csr => csr, :profile_name => 'server' }) }.to raise_error(ArgumentError, "You can't pass both :csr and :spki")
  end
  it "raise an error if you don't pass an R509::SPKI in :spki" do
    spki = OpenSSL::Netscape::SPKI.new(@spki)
    expect { @ca.sign({ :spki => spki, :profile_name => 'server' }) }.to raise_error(ArgumentError, 'You must pass an R509::SPKI object for :spki')
  end
  it "raise an error if you pass :spki without :subject" do
    spki = R509::SPKI.new(:spki => @spki)
    expect { @ca.sign({ :spki => spki, :profile_name => 'server' }) }.to raise_error(ArgumentError, 'You must supply :subject when passing :spki')
  end
  it "raise an error if you don't pass an R509::CSR in :csr" do
    csr = OpenSSL::X509::Request.new(@csr)
    expect { @ca.sign({ :csr => csr, :profile_name => 'server' }) }.to raise_error(ArgumentError, 'You must pass an R509::CSR object for :csr')
  end
  it "raises an error if you have no CAProfile with your CAConfig when attempting to issue a cert" do
    config = R509::Config::CAConfig.new(
      :ca_cert => TestFixtures.test_ca_cert
    )
    ca = R509::CertificateAuthority::Signer.new(config)
    expect { ca.sign(:csr => @csr)  }.to raise_error(R509::R509Error, 'You must have at least one CAProfile on your CAConfig to issue')
  end
  it "properly issues a cert with the default CAProfile configuration" do
    csr = R509::CSR.new(:subject => [["CN","testy.mctest"]], :bit_strength => 1024)
    ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
    config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
    profile = R509::Config::CAProfile.new
    config.set_profile("default",profile)
    ca = R509::CertificateAuthority::Signer.new(config)
    expect { ca.sign( :csr => csr, :profile_name => 'default') }.to_not raise_error
  end
  it "properly issues server cert using spki" do
    spki = R509::SPKI.new(:spki => @spki)
    cert = @ca.sign({ :spki => spki, :profile_name => 'server', :subject=>[['CN','test.local']]})
    cert.to_pem.should match(/BEGIN CERTIFICATE/)
    cert.subject.to_s.should == '/CN=test.local'
    cert.extended_key_usage.web_server_authentication?.should == true
  end
  it "properly issues server cert" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    cert = @ca.sign({ :csr => csr, :profile_name => 'server' })
    cert.to_pem.should match(/BEGIN CERTIFICATE/)
    cert.subject.to_s.should == '/C=US/ST=Illinois/L=Chicago/O=Paul Kehrer/CN=langui.sh'
    cert.extended_key_usage.web_server_authentication?.should == true
  end
  it "properly issues cert with all EKUs" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    config = R509::Config::CAConfig.from_yaml("all_eku_ca", File.read("#{File.dirname(__FILE__)}/fixtures/config_test_various.yaml"), {:ca_root_path => "#{File.dirname(__FILE__)}/fixtures"})
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign({ :csr => csr, :profile_name => 'smorgasbord' })
    cert.extended_key_usage.web_server_authentication?.should == true
    cert.extended_key_usage.web_client_authentication?.should == true
    cert.extended_key_usage.code_signing?.should == true
    cert.extended_key_usage.email_protection?.should == true
    cert.extended_key_usage.ocsp_signing?.should == true
    cert.extended_key_usage.time_stamping?.should == true
  end
  it "properly issues cert with OCSP noCheck in profile" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    config = R509::Config::CAConfig.from_yaml("ocsp_no_check_ca", File.read("#{File.dirname(__FILE__)}/fixtures/config_test_various.yaml"), {:ca_root_path => "#{File.dirname(__FILE__)}/fixtures"})
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign({ :csr => csr, :profile_name => 'ocsp_no_check_delegate' })
    cert.ocsp_no_check?.should == true
    cert.extended_key_usage.ocsp_signing?.should == true
  end
  it "does not encode noCheck if not specified by the profile" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    cert = @ca.sign({ :csr => csr, :profile_name => 'server' })
    cert.ocsp_no_check?.should == false
  end
  it "when supplied, uses subject_item_policy to determine allowed subject" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    cert = @ca.sign({ :csr => csr, :profile_name => 'server_with_subject_item_policy' })
    #profile requires C, ST, CN. O and OU are optional
    cert.subject.to_s.should == '/C=US/ST=Illinois/O=Paul Kehrer/CN=langui.sh'
  end
  it "raises error when issuing cert with csr that does not match subject_item_policy" do
    csr = R509::CSR.new(:csr => @csr)
    expect { @ca.sign({ :csr => csr, :profile_name => 'server_with_subject_item_policy' }) }.to raise_error(R509::R509Error, /This profile requires you supply/)
  end
  it "issues with specified (dnsName) san domains in array" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    san_names = ['langui.sh','domain2.com']
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :subject => csr.subject, :san_names => san_names )
    cert.san.dns_names.should == ['langui.sh','domain2.com']
  end
  it "issues with empty san_names array" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :subject => csr.subject, :san_names => [] )
    cert.san.should be_nil
  end
  it "issues with specified (directoryName and dnsName) san domains in array" do
    name = [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']]
    csr = R509::CSR.new(:subject => name, :bit_strength => 1024)
    san_names = ['langui.sh','domain2.com',name]
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :subject => csr.subject, :san_names => san_names )
    cert.san.dns_names.should == ['langui.sh','domain2.com']
    cert.san.directory_names.size.should == 1
    cert.san.directory_names[0].to_s.should == "/C=US/ST=Illinois/L=Chicago/O=Paul Kehrer/CN=langui.sh"
  end
  it "issues with specified san domains in R509::ASN1::GeneralNames object" do
    csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :bit_strength => 1024)
    san_names = R509::ASN1.general_name_parser(['langui.sh','domain2.com'])
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :subject => csr.subject, :san_names => san_names )
    cert.san.dns_names.should == ['langui.sh','domain2.com']
  end
  it "issues with san domains from csr" do
    csr = R509::CSR.new(:csr => @csr)
    cert = @ca.sign(:csr => csr, :profile_name => 'server')
    cert.san.dns_names.should == ['test.local','additionaldomains.com','saniam.com']
  end
  it "issues a csr made via array" do
    csr = R509::CSR.new(:subject => [['CN','langui.sh']], :bit_strength => 1024)
    cert = @ca.sign(:csr => csr, :profile_name => 'server')
    cert.subject.to_s.should == '/CN=langui.sh'
  end
  it "overrides a CSR's subject with :subject" do
    csr = R509::CSR.new(:csr => @csr)
    subject = csr.subject
    subject.CN = "someotherdomain.com"
    subject.delete("O")
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :subject => subject )
    cert.subject.to_s.should == '/CN=someotherdomain.com'
  end
  it "tests that policy identifiers are properly encoded" do
    csr = R509::CSR.new(:csr => @csr)
    cert = @ca.sign(:csr => csr, :profile_name => 'server')
    cert.certificate_policies.should_not be_nil
    cert.certificate_policies.policies.count.should == 1
    cert.certificate_policies.policies[0].policy_identifier.should == "2.16.840.1.12345.1.2.3.4.1"
    cert.certificate_policies.policies[0].policy_qualifiers.cps_uris.should == ["http://example.com/cps", "http://other.com/cps"]
    cert.certificate_policies.policies[0].policy_qualifiers.user_notices.count.should == 1
    un = cert.certificate_policies.policies[0].policy_qualifiers.user_notices[0]
    un.notice_reference.notice_numbers.should == [1,2,3,4]
    un.notice_reference.organization.should == 'my org'
    un.explicit_text.should == "thing"
  end
  it "multiple policy identifiers are properly encoded" do
    csr = R509::CSR.new(:csr => @csr)
    config = R509::Config::CAConfig.from_yaml("multi_policy_ca", File.read("#{File.dirname(__FILE__)}/fixtures/config_test_various.yaml"), {:ca_root_path => "#{File.dirname(__FILE__)}/fixtures"})
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign(:csr => csr, :profile_name => 'server')
    cert.certificate_policies.should_not be_nil
    cert.certificate_policies.policies.count.should == 3
    p0 = cert.certificate_policies.policies[0]
    p0.policy_identifier.should == "2.16.840.1.99999.21.234"
    p0.policy_qualifiers.cps_uris.should == ["http://example.com/cps", "http://haha.com"]
    p0.policy_qualifiers.user_notices.count.should == 1
    un0 = p0.policy_qualifiers.user_notices[0]
    un0.notice_reference.notice_numbers.should == [1,2,3]
    un0.notice_reference.organization.should == "my org"
    un0.explicit_text.should == "this is a great thing"
    p1 = cert.certificate_policies.policies[1]
    p1.policy_identifier.should == "2.16.840.1.99999.21.235"
    p1.policy_qualifiers.cps_uris.should == ["http://example.com/cps2"]
    p1.policy_qualifiers.user_notices.count.should == 2
    un1 = p1.policy_qualifiers.user_notices[0]
    un1.notice_reference.notice_numbers.should == [3,2,1]
    un1.notice_reference.organization.should == "another org"
    un1.explicit_text.should == 'this is a bad thing'
    un2 = p1.policy_qualifiers.user_notices[1]
    un2.notice_reference.should be_nil
    un2.explicit_text.should == "another user notice"
    p2 = cert.certificate_policies.policies[2]
    p2.policy_identifier.should == "2.16.840.1.99999.0"
    p2.policy_qualifiers.should be_nil
  end
  it "issues a certificate with an authority key identifier" do
    csr = R509::CSR.new(:csr => @csr)
    cert = @ca.sign(:csr => csr, :profile_name => 'server')
    cert.authority_key_identifier.should_not be_nil
  end
  context "inhibitAnyPolicy" do
    it "issues without inhibit any policy when not present" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.inhibit_any_policy.should == nil
    end
    it "issues with inhibit any policy when present" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:inhibit_any_policy => 1)
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.inhibit_any_policy.skip_certs.should == 1
    end
  end
  context "policyConstraints" do
    it "issues without policy constraints when not present" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.policy_constraints.should == nil
    end
    it "issues with require_explicit_policy" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:policy_constraints => {"require_explicit_policy" => 3})
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.policy_constraints.require_explicit_policy.should == 3
      cert.policy_constraints.inhibit_policy_mapping.should == nil
    end
    it "issues with inhibit_policy_mapping" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:policy_constraints => {"inhibit_policy_mapping" => 3})
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.policy_constraints.require_explicit_policy.should == nil
      cert.policy_constraints.inhibit_policy_mapping.should == 3
    end
    it "issues with both require and inhibit" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:policy_constraints => {"require_explicit_policy" => 3, "inhibit_policy_mapping" => 2})
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.policy_constraints.require_explicit_policy.should == 3
      cert.policy_constraints.inhibit_policy_mapping.should == 2
    end
  end
  context "nameConstraints" do
    it "issues with no constraints if not present in profile" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.name_constraints.should be_nil
    end
    it "issues with permitted constraints" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:name_constraints => { "permitted" => [ { "type" => "DNS", "value" => "domain.com" } , { "type" => "IP", "value" => "ff::/ff:ff:ff:ff:ff:ff:ff:ff" } ] } )
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.name_constraints.permitted_names[0].type.should == :dNSName
      cert.name_constraints.permitted_names[0].value.should == 'domain.com'
      cert.name_constraints.permitted_names[1].type.should == :iPAddress
      cert.name_constraints.permitted_names[1].value.should == 'ff::/ff:ff:ff:ff:ff:ff:ff:ff'
    end
    it "issues with excluded constraints" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:name_constraints => { "excluded" => [ { "type" => "dirName", "value" => [["CN","domain.com"]] }, { "type" => "URI", "value" => ".domain.com" } ] } )
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.name_constraints.excluded_names[0].type.should == :directoryName
      cert.name_constraints.excluded_names[0].value.to_s.should == '/CN=domain.com'
      cert.name_constraints.excluded_names[1].type.should == :uniformResourceIdentifier
      cert.name_constraints.excluded_names[1].value.to_s.should == '.domain.com'
    end
    it "issues with both constraints" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      profile = R509::Config::CAProfile.new(:name_constraints => { "permitted" => [ { "type" => "DNS", "value" => "domain.com" } ], "excluded" => [ { "type" => "dirName", "value" => [["CN","domain.com"]] } ] } )
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.name_constraints.permitted_names[0].type.should == :dNSName
      cert.name_constraints.permitted_names[0].value.should == 'domain.com'
      cert.name_constraints.excluded_names[0].type.should == :directoryName
      cert.name_constraints.excluded_names[0].value.to_s.should == '/CN=domain.com'
    end
  end
  context "authorityInfoAccess" do
    it "issues a certificate with a ca_issuers_location and ocsp_location" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ca_issuers_location = ['http://domain.com/ca.html']
      config.ocsp_location = ['http://ocsp.domain.com','http://ocsp.other.com']
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.authority_info_access.ca_issuers.uris.should == ["http://domain.com/ca.html"]
      cert.authority_info_access.ocsp.uris.should == ["http://ocsp.domain.com","http://ocsp.other.com"]
    end
    it "issues a certificate with a ca_issuers_location and ocsp_location (dirName,URI,DNS)" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ca_issuers_location = ['http://domain.com/ca.html','domain.com',R509::Subject.new([['CN','myDir'],['C','US']])]
      config.ocsp_location = ['http://ocsp.domain.com/','ocsp.domain.com',R509::Subject.new([['CN','ocsp'],['L','Locality']])]
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.authority_info_access.ca_issuers.uris.should == ["http://domain.com/ca.html"]
      cert.authority_info_access.ca_issuers.dns_names.should == ['domain.com']
      cert.authority_info_access.ca_issuers.directory_names[0].to_s.should == '/CN=myDir/C=US'
      cert.authority_info_access.ocsp.uris.should == ["http://ocsp.domain.com/"]
      cert.authority_info_access.ocsp.dns_names.should == ["ocsp.domain.com"]
      cert.authority_info_access.ocsp.directory_names[0].to_s.should == '/CN=ocsp/L=Locality'
    end
    it "issues a certificate with a ca_issuers_location and no ocsp_location" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ca_issuers_location = ['http://domain.com/ca.html']
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign(:csr => csr, :profile_name => 'default')
      cert.authority_info_access.ca_issuers.uris.should == ["http://domain.com/ca.html"]
      cert.authority_info_access.ocsp.uris.should == []
    end
    it "issues a certificate with multiple ca_issuer_locations" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ca_issuers_location = ["http://somelocation.com/c.html","http://other.com/d.html"]
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign( :csr => csr, :profile_name => 'default')
      cert.authority_info_access.ocsp.uris.should == []
      cert.authority_info_access.ca_issuers.uris.should == ["http://somelocation.com/c.html","http://other.com/d.html"]
    end
    it "issues a certificate with ocsp_location" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ocsp_location = ["http://myocsp.jb.net"]
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign( :csr => csr, :profile_name => 'default')
      cert.authority_info_access.ca_issuers.uris.should == []
      cert.authority_info_access.ocsp.uris.should == ["http://myocsp.jb.net"]
    end
    it "issues a certificate with an empty array for ocsp_location" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ocsp_location = []
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign( :csr => csr, :profile_name => 'default')
      cert.authority_info_access.should be_nil
    end
    it "issues a certificate with an empty array for ca_issuers_location" do
      csr = R509::CSR.new(:csr => @csr)
      ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
      config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
      config.ca_issuers_location = []
      profile = R509::Config::CAProfile.new
      config.set_profile("default",profile)
      ca = R509::CertificateAuthority::Signer.new(config)
      cert = ca.sign( :csr => csr, :profile_name => 'default')
      cert.authority_info_access.should be_nil
    end
  end
  it "issues a certificate with no CDP" do
    csr = R509::CSR.new(:csr => @csr)
    ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
    config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
    profile = R509::Config::CAProfile.new
    config.set_profile("default",profile)
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign( :csr => csr, :profile_name => 'default')
    cert.crl_distribution_points.should == nil
  end
  it "issues a certificate with an empty array for CDP" do
    csr = R509::CSR.new(:csr => @csr)
    ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
    config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
    config.cdp_location = []
    profile = R509::Config::CAProfile.new
    config.set_profile("default",profile)
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign( :csr => csr, :profile_name => 'default')
    cert.crl_distribution_points.should be_nil
  end
  it "issues a certificate with a single CDP" do
    csr = R509::CSR.new(:csr => @csr)
    ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
    config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
    config.cdp_location = ["http://mycdp.com/x.crl"]
    profile = R509::Config::CAProfile.new
    config.set_profile("default",profile)
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign( :csr => csr, :profile_name => 'default')
    cert.crl_distribution_points.crl.uris.should == ["http://mycdp.com/x.crl"]
  end
  it "issues a certificate with multiple CDPs" do
    csr = R509::CSR.new(:csr => @csr)
    ca_cert = R509::Cert.new( :cert => TestFixtures::TEST_CA_CERT, :key => TestFixtures::TEST_CA_KEY )
    config = R509::Config::CAConfig.new(:ca_cert => ca_cert)
    config.cdp_location = ["http://mycdp.com/x.crl","http://anothercrl.com/x.crl"]
    profile = R509::Config::CAProfile.new
    config.set_profile("default",profile)
    ca = R509::CertificateAuthority::Signer.new(config)
    cert = ca.sign( :csr => csr, :profile_name => 'default')
    cert.crl_distribution_points.crl.uris.should == ["http://mycdp.com/x.crl","http://anothercrl.com/x.crl"]
  end
  it "tests basic constraints CA:TRUE and pathlen:0 on a subroot" do
    csr = R509::CSR.new(:csr => @csr)
    cert = @ca.sign(:csr => csr, :profile_name => 'subroot')
    cert.basic_constraints.is_ca?.should == true
    cert.basic_constraints.path_length.should == 0
  end
  it "issues with md5" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'md5')
    cert.cert.signature_algorithm.should == 'md5WithRSAEncryption'
  end
  it "issues with sha1" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'sha1')
    cert.cert.signature_algorithm.should == 'sha1WithRSAEncryption'
  end
  it "issues with sha224" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'sha224')
    cert.cert.signature_algorithm.should == 'sha224WithRSAEncryption'
  end
  it "issues with sha256" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'sha256')
    cert.cert.signature_algorithm.should == 'sha256WithRSAEncryption'
  end
  it "issues with sha384" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'sha384')
    cert.cert.signature_algorithm.should == 'sha384WithRSAEncryption'
  end
  it "issues with sha512" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'sha512')
    cert.cert.signature_algorithm.should == 'sha512WithRSAEncryption'
  end
  it "issues with invalid hash (sha1 fallback)" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => 'server', :message_digest => 'invalid')
    cert.cert.signature_algorithm.should == 'sha1WithRSAEncryption'
  end
  it "generates random serial when serial is not specified and uses microtime as part of the serial to prevent collision" do
    now = Time.now
    Time.stub!(:now).and_return(now)
    time = now.to_i.to_s
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => "server")
    cert.serial.to_s.size.should >= 45
    cert.serial.to_s.index(time).should_not be_nil
  end
  it "accepts specified serial number" do
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => "server", :serial => 12345)
    cert.serial.should == 12345
  end
  it "has default notBefore/notAfter dates" do
    not_before = (Time.now - (6 * 60 * 60)).utc
    not_after = (Time.now - (6 * 60 * 60) + (365 * 24 * 60 * 60)).utc
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => "server")
    cert.cert.not_before.year.should == not_before.year
    cert.cert.not_before.month.should == not_before.month
    cert.cert.not_before.day.should == not_before.day
    cert.cert.not_before.hour.should == not_before.hour
    cert.cert.not_before.min.should == not_before.min
    cert.cert.not_after.year.should == not_after.year
    cert.cert.not_after.month.should == not_after.month
    cert.cert.not_after.day.should == not_after.day
    cert.cert.not_after.hour.should == not_after.hour
    cert.cert.not_after.min.should == not_after.min
  end
  it "allows you to specify notBefore/notAfter dates" do
    not_before = Time.now - 5 * 60 * 60
    not_after = Time.now + 5 * 60 * 60
    csr = R509::CSR.new(:csr => @csr3)
    cert = @ca.sign(:csr => csr, :profile_name => "server", :not_before => not_before, :not_after => not_after)
    cert.cert.not_before.ctime.should == not_before.utc.ctime
    cert.cert.not_after.ctime.should == not_after.utc.ctime
  end
  it "issues a certificate from a root that does not have a subjectKeyIdentifier" do
    config = R509::Config::CAConfig.from_yaml("missing_key_identifier_ca", File.read("#{File.dirname(__FILE__)}/fixtures/config_test_various.yaml"), {:ca_root_path => "#{File.dirname(__FILE__)}/fixtures"})
    ca = R509::CertificateAuthority::Signer.new(config)
    csr = R509::CSR.new(:csr => @csr3)
    cert = ca.sign(:csr => csr, :profile_name => "server")
    cert.authority_key_identifier.should == nil
    cert.extended_key_usage.web_server_authentication?.should == true
  end
  it "raises error unless you provide a proper config (or nil)" do
    expect { R509::CertificateAuthority::Signer.new('invalid') }.to raise_error(R509::R509Error, 'config must be a kind of R509::Config::CAConfig or nil (for self-sign only)')
  end
  it "raises error when providing invalid ca profile" do
    csr = R509::CSR.new(:csr => @csr)
    expect { @ca.sign(:csr => csr, :profile_name => 'invalid') }.to raise_error(R509::R509Error, "unknown profile 'invalid'")
  end
  it "raises error when attempting to issue CSR with invalid signature" do
    csr = R509::CSR.new(:csr => @csr_invalid_signature)
    expect { @ca.sign(:csr => csr, :profile_name => 'server') }.to raise_error(R509::R509Error, 'Certificate request signature is invalid.')
  end
  it "raises error when passing non-hash to selfsign method" do
    expect { @ca.selfsign(@csr) }.to raise_error(ArgumentError, "You must pass a hash of options consisting of at minimum :csr")
  end
  it "raises error when passing invalid data for san_names" do
    csr = R509::CSR.new(
      :subject => [['C','US'],['O','r509 LLC'],['CN','r509 Self-Signed CA Test']],
      :bit_strength => 1024
    )
    san_names = "invalid"
    expect { @ca.selfsign(:csr => csr, :san_names => san_names) }.to raise_error(ArgumentError,'When passing SAN names it must be provided as either an array of strings or an R509::ASN1::GeneralNames object')
  end
  it "issues a self-signed certificate with custom fields" do
    not_before = Time.now.to_i
    not_after = Time.now.to_i+3600*24*7300
    csr = R509::CSR.new(
      :subject => [['C','US'],['O','r509 LLC'],['CN','r509 Self-Signed CA Test']],
      :bit_strength => 1024
    )
    san_names = R509::ASN1.general_name_parser(['sanname1','sanname2'])
    cert = @ca.selfsign(
      :csr => csr,
      :serial => 3,
      :not_before => not_before,
      :not_after => not_after,
      :message_digest => 'sha256',
      :san_names => san_names
    )
    cert.public_key.to_s.should == csr.public_key.to_s
    cert.signature_algorithm.should == 'sha256WithRSAEncryption'
    cert.serial.should == 3
    cert.not_before.to_i.should == not_before
    cert.not_after.to_i.should == not_after
    cert.subject.to_s.should == '/C=US/O=r509 LLC/CN=r509 Self-Signed CA Test'
    cert.issuer.to_s.should == '/C=US/O=r509 LLC/CN=r509 Self-Signed CA Test'
    cert.basic_constraints.is_ca?.should == true
    cert.san.dns_names.should include('sanname1','sanname2')
  end
  it "issues a self-signed certificate with san names provided as an array" do
    not_before = Time.now.to_i
    not_after = Time.now.to_i+3600*24*7300
    csr = R509::CSR.new(
      :subject => [['C','US'],['O','r509 LLC'],['CN','r509 Self-Signed CA Test']],
      :bit_strength => 1024
    )
    san_names = ['sanname1','sanname2']
    cert = @ca.selfsign(
      :csr => csr,
      :not_before => not_before,
      :not_after => not_after,
      :message_digest => 'sha256',
      :san_names => san_names
    )
    cert.san.dns_names.should include('sanname1','sanname2')
  end
  it "issues self-signed certificate with SAN in CSR" do
    csr = R509::CSR.new(
      :subject => [['CN','My Self Sign']],
      :san_names => ['sanname1','sanname2'],
      :bit_strength => 1024
    )
    cert = @ca.selfsign(
      :csr => csr
    )
    cert.san.dns_names.should include('sanname1','sanname2')
    cert.subject.to_s.should == '/CN=My Self Sign'
    cert.issuer.to_s.should == '/CN=My Self Sign'
    cert.public_key.to_s.should == csr.public_key.to_s
  end
  it "issues a self-signed certificate with defaults" do
    csr = R509::CSR.new(
      :subject => [['C','US'],['O','r509 LLC'],['CN','r509 Self-Signed CA Test']],
      :bit_strength => 1024
    )
    cert = @ca.selfsign(
      :csr => csr
    )
    cert.public_key.to_s.should == csr.public_key.to_s
    cert.signature_algorithm.should == 'sha1WithRSAEncryption'
    (cert.not_after.to_i-cert.not_before.to_i).should == 31536000
    cert.subject.to_s.should == '/C=US/O=r509 LLC/CN=r509 Self-Signed CA Test'
    cert.issuer.to_s.should == '/C=US/O=r509 LLC/CN=r509 Self-Signed CA Test'
    cert.basic_constraints.is_ca?.should == true
  end
  it "raises an error if attempting to self-sign without a key" do
    csr = R509::CSR.new(:csr => @csr3)
    expect { @ca.selfsign( :csr => csr ) }.to raise_error(ArgumentError, "CSR must also have a private key to self sign")
  end
  it "raises an error if you call sign without passing a config to the object" do
    ca_signer = R509::CertificateAuthority::Signer.new
    csr = R509::CSR.new(:csr => @csr3)
    expect { ca_signer.sign(:csr => csr, :profile_name => "server") }.to raise_error(R509::R509Error, "When instantiating the signer without a config you can only call #selfsign")
  end

  context "issuing off an elliptic curve CA", :ec => true do
    before :all do
      @test_ca_ec = R509::Config::CAConfig.from_yaml("test_ca_ec", File.read("#{File.dirname(__FILE__)}/fixtures/config_test_ec.yaml"), {:ca_root_path => "#{File.dirname(__FILE__)}/fixtures"})
      @ca_ec = R509::CertificateAuthority::Signer.new(@test_ca_ec)
    end

    it "properly issues server cert" do
      csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :type => :ec)
      cert = @ca_ec.sign( :csr => csr, :profile_name => 'server' )
      cert.to_pem.should match(/BEGIN CERTIFICATE/)
      cert.subject.to_s.should == '/C=US/ST=Illinois/L=Chicago/O=Paul Kehrer/CN=langui.sh'
      cert.signature_algorithm.should == 'ecdsa-with-SHA384'
      cert.key_algorithm.should == :ec
      cert.extended_key_usage.web_server_authentication?.should == true
    end
    it "properly issues server cert using spki" do
      spki = R509::SPKI.new(:spki => @spki)
      cert = @ca_ec.sign( :spki => spki, :profile_name => 'server', :subject=>[['CN','test.local']] )
      cert.to_pem.should match(/BEGIN CERTIFICATE/)
      cert.subject.to_s.should == '/CN=test.local'
      cert.signature_algorithm.should == 'ecdsa-with-SHA384'
      cert.key_algorithm.should == :rsa #weird right?! it's because the spki is RSA even though the signature is from an EC root
      cert.extended_key_usage.web_server_authentication?.should == true
    end
  end

  context "issuing off a DSA CA" do
    before :all do
      @test_ca_dsa = R509::Config::CAConfig.from_yaml("test_ca_dsa", File.read("#{File.dirname(__FILE__)}/fixtures/config_test_dsa.yaml"), {:ca_root_path => "#{File.dirname(__FILE__)}/fixtures"})
      @ca_dsa = R509::CertificateAuthority::Signer.new(@test_ca_dsa)
    end

    it "properly issues server cert" do
      csr = R509::CSR.new(:subject => [['C','US'],['ST','Illinois'],['L','Chicago'],['O','Paul Kehrer'],['CN','langui.sh']], :type => :dsa, :bit_strength => 1024)
      cert = @ca_dsa.sign( :csr => csr, :profile_name => 'server' )
      cert.to_pem.should match(/BEGIN CERTIFICATE/)
      cert.subject.to_s.should == '/C=US/ST=Illinois/L=Chicago/O=Paul Kehrer/CN=langui.sh'
      cert.signature_algorithm.should == 'dsaWithSHA1'
      cert.key_algorithm.should == :dsa
      cert.extended_key_usage.web_server_authentication?.should == true
    end
  end
end
