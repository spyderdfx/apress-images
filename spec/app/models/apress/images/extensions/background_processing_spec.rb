require 'spec_helper'

RSpec.describe Apress::Images::Extensions::BackgroundProcessing do
  describe '.process_in_background' do
    it do
      expect(DelayedImage.attachment_definitions[:img][:delayed]).to have_key(:processing_image_url)
      expect(DelayedImage.attachment_definitions[:img][:delayed][:processing_image_url]).to eq(
        described_class::DEFAULT_PROCESSING_IMAGE_PATH
      )
      expect(DelayedImage.attachment_definitions[:img][:delayed]).to have_key(:queue_name)
    end
  end

  describe '#enqueue_delayed_processing' do
    let(:image) { build :delayed_image }

    before { allow(Resque).to receive(:enqueue_to) }

    context 'when update processing field' do
      before { image.save! }

      it { expect(image).to be_processing }
    end

    context 'when enqueing' do
      context 'online processing' do
        before do
          image.online_processing = true
          image.save!
        end

        it do
          expect(Resque).to have_received(:enqueue_to).with(Apress::Images::ProcessJob.queue,
                                                            Apress::Images::ProcessJob,
                                                            image.id,
                                                            image.class.name,
                                                            {})
        end
      end

      context 'non online processing' do
        before do
          image.online_processing = false
          image.save!
        end

        it do
          expect(Resque).to have_received(:enqueue_to).with(Apress::Images::ProcessJob.non_online_queue,
                                                            Apress::Images::ProcessJob,
                                                            image.id,
                                                            image.class.name,
                                                            {})
        end
      end

      context 'with croping' do
        let(:image) { build :delayed_image_with_crop }

        before do
          image.online_processing = false
        end

        context 'when crop_ attributes are specified' do
          before do
            image.assign_attributes(crop_w: '100', crop_h: '100', crop_x: '0', crop_y: '10')
            image.save!
          end

          it 'passes those attributes as last argument to enqueue_to' do
            expect(Resque).to have_received(:enqueue_to).with(Apress::Images::ProcessJob.non_online_queue,
                                                              Apress::Images::ProcessJob,
                                                              image.id,
                                                              image.class.name,
                                                              assign_attributes: {
                                                                crop_w: "100", crop_h: "100", crop_x: "0", crop_y: "10"
                                                              })
          end
        end

        context 'when crop_ attributes are not specified' do
          before do
            image.save!
          end

          it 'does not pass those attributes to enqueue_to' do
            expect(Resque).to have_received(:enqueue_to).with(Apress::Images::ProcessJob.non_online_queue,
                                                              Apress::Images::ProcessJob,
                                                              image.id,
                                                              image.class.name,
                                                              {})
          end
        end
      end
    end

    context 'when model saved twice in transaction' do
      before do
        allow(Resque).to receive(:enqueue_to).with(Apress::Images::ProcessJob.queue,
                                                   Apress::Images::ProcessJob,
                                                   instance_of(Fixnum),
                                                   image.class.name,
                                                   {})
        allow(image).to receive(:corrupted_image_file_validation).and_return(true)
        ActiveRecord::Base.transaction do
          image.save!
          image.img_updated_at = image.img_updated_at + 1.day
          image.save!
        end
      end

      it do
        expect(image).to be_processing
        expect(Resque).to have_received(:enqueue_to).with(Apress::Images::ProcessJob.queue,
                                                          Apress::Images::ProcessJob,
                                                          image.id,
                                                          image.class.name,
                                                          {}).once
      end
    end
  end

  describe 'destruction' do
    let(:redis) { Resque.redis }
    let(:image) { build :delayed_image }
    let(:image_stub) { Rails.root.join('public/images/stub_thumb.gif') }

    context 'when online pricessing' do
      before do
        image.online_processing = true
        image.save!
      end

      it do
        expect { image.destroy }.to change { redis.lrange('queue:images', 0, -1).count }.from(1).to(0)
        expect(image).to be_destroyed
        expect(image).not_to be_processing # resets the processing flag
        expect(File.exist?(image_stub)).to eq(true) # keeps the stub image
      end
    end

    context 'when non-online processing' do
      before do
        image.online_processing = false
        image.save!
      end

      it do
        expect { image.destroy }.to change { redis.lrange('queue:non_online_images', 0, -1).count }.from(1).to(0)
        expect(image).to be_destroyed
        expect(image).not_to be_processing # resets the processing flag
        expect(File.exist?(image_stub)).to eq(true) # keeps the stub image
      end
    end
  end
end
