module Spaceship
  module Tunes
    class Application < TunesBase
      # @return (String) The App identifier of this app, provided by iTunes Connect
      # @example
      #   "1013943394"
      attr_accessor :apple_id

      # @return (String) The name you provided for this app (in the default language)
      # @example
      #   "Spaceship App"
      attr_accessor :name

      # @return (String) the supported platform of this app
      # @example
      #   "ios"
      attr_accessor :platform

      # @return (String) The Vendor ID provided by iTunes Connect
      # @example
      #   "1435592086"
      attr_accessor :vendor_id

      # @return (String) The bundle_id (app identifier) of your app
      # @example
      #   "com.krausefx.app"
      attr_accessor :bundle_id

      # @return (String) Last modified
      attr_accessor :last_modified

      # @return (Integer) The number of issues provided by iTunes Connect
      attr_accessor :issues_count

      # @return (String) The URL to a low resolution app icon of this app (340x340px). Might be nil
      # @example
      #   "https://is1-ssl.mzstatic.com/image/thumb/Purple7/v4/cd/a3/e2/cda3e2ac-4034-c6af-ee0c-3e4d9a0bafaa/pr_source.png/340x340bb-80.png"
      # @example
      #   nil
      attr_accessor :app_icon_preview_url

      attr_mapping(
        'adamId' => :apple_id,
        'name' => :name,
        'appType' => :platform,
        'vendorId' => :vendor_id,
        'bundleId' => :bundle_id,
        'lastModifiedDate' => :last_modified,
        'issuesCount' => :issues_count,
        'iconUrl' => :app_icon_preview_url
      )

      class << self
        # Create a new object based on a hash.
        # This is used to create a new object based on the server response.
        def factory(attrs)
          return self.new(attrs)
        end

        # @return (Array) Returns all apps available for this account
        def all
          client.applications.map { |application| self.factory(application) }
        end

        # @return (Spaceship::Tunes::Application) Returns the application matching the parameter
        #   as either the App ID or the bundle identifier
        def find(identifier)
          all.find do |app|
            (app.apple_id == identifier.to_s or app.bundle_id == identifier)
          end
        end

        # Creates a new application on iTunes Connect
        # @param name (String): The name of your app as it will appear on the App Store.
        #   This can't be longer than 255 characters.
        # @param primary_language (String): If localized app information isn't available in an
        #   App Store territory, the information from your primary language will be used instead.
        # @param version (String): The version number is shown on the App Store and should
        #   match the one you used in Xcode.
        # @param sku (String): A unique ID for your app that is not visible on the App Store.
        # @param bundle_id (String): The bundle ID must match the one you used in Xcode. It
        #   can't be changed after you submit your first build.
        # @param company_name (String): The company name or developer name to display on the App Store for your apps.
        # It cannot be changed after you create your first app.
        def create!(name: nil, primary_language: nil, version: nil, sku: nil, bundle_id: nil, bundle_id_suffix: nil, company_name: nil)
          client.create_application!(name: name,
                         primary_language: primary_language,
                                  version: version,
                                      sku: sku,
                                bundle_id: bundle_id,
                                bundle_id_suffix: bundle_id_suffix,
                                company_name: company_name)
        end
      end

      #####################################################
      # @!group Getting information
      #####################################################

      # @return (Spaceship::AppVersion) Receive the version that is currently live on the
      #  App Store. You can't modify all values there, so be careful.
      def live_version
        if raw_data['versions'].count == 1
          v = raw_data['versions'].last
          if ['Prepare for Upload', 'prepareForUpload'].include?(v['state']) # this only applies for the initial version
            return nil
          end
        end

        Spaceship::AppVersion.find(self, self.apple_id, true)
      end

      # @return (Spaceship::AppVersion) Receive the version that can fully be edited
      def edit_version
        if raw_data['versions'].count == 1
          v = raw_data['versions'].last

          # this only applies for the initial version
          # no idea why it's sometimes the short code and sometimes the long one
          unless ['Prepare for Upload', 'Developer Rejected', 'devRejected', 'Rejected', 'prepareForUpload'].include?(v['state'])
            return nil # only live version, user should create a new version
          end
        end

        Spaceship::AppVersion.find(self, self.apple_id, false)
      end

      # @return (Spaceship::AppVersion) This will return the `edit_version` if available
      #   and fallback to the `edit_version`. Use this to just access the latest data
      def latest_version
        edit_version || live_version || Spaceship::AppVersion.find(self, self.apple_id, false) # we want to get *any* version, prefered the latest one
      end

      # @return (String) An URL to this specific resource. You can enter this URL into your browser
      def url
        "https://itunesconnect.apple.com/WebObjects/iTunesConnect.woa/ra/ng/app/#{self.apple_id}"
      end

      # @return (Hash) Contains the reason for rejection.
      #  if everything is alright, the result will be
      #  `{"sectionErrorKeys"=>[], "sectionInfoKeys"=>[], "sectionWarningKeys"=>[], "replyConstraints"=>{"minLength"=>1, "maxLength"=>4000}, "appNotes"=>{"threads"=>[]}, "betaNotes"=>{"threads"=>[]}, "appMessages"=>{"threads"=>[]}}`
      def resolution_center
        client.get_resolution_center(apple_id)
      end

      def details
        attrs = client.app_details(apple_id)
        attrs.merge!(application: self)
        Tunes::AppDetails.factory(attrs)
      end

      #####################################################
      # @!group Modifying
      #####################################################

      # Create a new version of your app
      # Since we have stored the outdated raw_data, we need to refresh this object
      # otherwise `edit_version` will return nil
      def create_version!(version_number)
        if edit_version
          raise "Cannot create a new version for this app as there already is an `edit_version` available"
        end

        client.create_version!(apple_id, version_number)

        # Future: implemented -reload method
      end

      # Will make sure the current edit_version matches the given version number
      # This will either create a new version or change the version number
      # from an existing version
      # @return (Bool) Was something changed?
      def ensure_version!(version_number)
        if (e = edit_version)
          if e.version.to_s != version_number.to_s
            # Update an existing version
            e.version = version_number
            e.save!
            return true
          end
          return false
        else
          create_version!(version_number)
          return true
        end
      end

      # set the price tier. This method doesn't require `save` to be called
      def update_price_tier!(price_tier)
        client.update_price_tier!(self.apple_id, price_tier)
      end

      # The current price tier
      def price_tier
        client.price_tier(self.apple_id)
      end

      #####################################################
      # @!group Builds
      #####################################################

      # A reference to all the build trains
      # @return [Hash] a hash, the version number being the key
      def build_trains
        Tunes::BuildTrain.all(self, self.apple_id)
      end

      # @return [Array]A list of binaries which are not even yet processing based on the version
      #   These are all build that have no information except the upload date
      #   Those builds can also be the builds that are stuck on iTC.
      def pre_processing_builds
        data = client.build_trains(apple_id, 'internal') # we need to fetch all trains here to get the builds

        builds = data.fetch('processingBuilds', []).collect do |attrs|
          attrs.merge!(build_train: self)
          Tunes::ProcessingBuild.factory(attrs)
        end

        builds.delete_if { |a| a.state == "ITC.apps.betaProcessingStatus.InvalidBinary" }

        builds
      end

      # @return [Array] This will return an array of *all* processing builds
      #   this include pre-processing or standard processing
      def all_processing_builds
        builds = self.pre_processing_builds

        self.build_trains.each do |version_number, train|
          train.processing_builds.each do |build|
            builds << build
          end
        end

        return builds
      end

      # Get all builds that are already processed for all build trains
      # You can either use the return value (array) or pass a block
      def builds
        all_builds = []
        self.build_trains.each do |version_number, train|
          train.builds.each do |build|
            yield(build) if block_given?
            all_builds << build unless block_given?
          end
        end
        all_builds
      end

      #####################################################
      # @!group Submit for Review
      #####################################################

      def create_submission
        version = self.latest_version
        if version.nil?
          raise "Could not find a valid version to submit for review"
        end

        Spaceship::AppSubmission.create(self, version)
      end

      # Cancels all ongoing TestFlight beta submission for this application
      def cancel_all_testflight_submissions!
        self.builds do |build|
          begin
            build.cancel_beta_review!
          rescue
            # We really don't care about any errors here
          end
        end
        true
      end

      #####################################################
      # @!group General
      #####################################################
      def setup
      end

      #####################################################
      # @!group Testers
      #####################################################

      # Add all testers (internal and external) to the current app list
      def add_all_testers!
        Tunes::Tester.external.add_all_to_app!(self.apple_id)
        Tunes::Tester.internal.add_all_to_app!(self.apple_id)
      end

      # @return (Array) Returns all external testers available for this app
      def external_testers
        Tunes::Tester.external.all_by_app(self.apple_id)
      end

      # @return (Array) Returns all internal testers available for this app
      def internal_testers
        Tunes::Tester.internal.all_by_app(self.apple_id)
      end

      # @return (Spaceship::Tunes::Tester.external) Returns the external tester matching the parameter
      #   as either the Tester id or email
      # @param identifier (String) (required): Value used to filter the tester
      def find_external_tester(identifier)
        Tunes::Tester.external.find_by_app(self.apple_id, identifier)
      end

      # @return (Spaceship::Tunes::Tester.internal) Returns the internal tester matching the parameter
      #   as either the Tester id or email
      # @param identifier (String) (required): Value used to filter the tester
      def find_internal_tester(identifier)
        Tunes::Tester.internal.find_by_app(self.apple_id, identifier)
      end

      # Add external tester to the current app list, if it doesn't exist will be created
      # @param email (String) (required): The email of the tester
      # @param first_name (String) (optional): The first name of the tester (Ignored if user already exist)
      # @param last_name (String) (optional): The last name of the tester (Ignored if user already exist)
      def add_external_tester!(email: nil, first_name: nil, last_name: nil)
        raise "Tester is already on #{self.name} betatesters" if find_external_tester(email)

        tester = Tunes::Tester.external.find(email) || Tunes::Tester.external.create!(email: email,
                                                                                 first_name: first_name,
                                                                                  last_name: last_name)
        tester.add_to_app!(self.apple_id)
      end

      # Remove external tester from the current app list that matching the parameter
      #   as either the Tester id or email
      # @param identifier (String) (required): Value used to filter the tester
      def remove_external_tester!(identifier)
        tester = find_external_tester(identifier)

        raise "Tester is not on #{self.name} betatesters" unless tester

        tester.remove_from_app!(self.apple_id)
      end
    end
  end
end
