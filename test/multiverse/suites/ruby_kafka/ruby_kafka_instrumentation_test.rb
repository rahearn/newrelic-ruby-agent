# This file is distributed under New Relic's license terms.
# See https://github.com/newrelic/newrelic-ruby-agent/blob/main/LICENSE for complete details.
# frozen_string_literal: true

class RubyKafkaInstrumentationTest < Minitest::Test
  def setup
    @topic = 'ruby-test-topic' + Time.now.to_i.to_s
    @stats_engine = NewRelic::Agent.instance.stats_engine
  end

  def teardown
    harvest_span_events!
    harvest_transaction_events!
    NewRelic::Agent.instance.stats_engine.clear_stats
    mocha_teardown
  end

  def test_produce_creates_span_metrics
    in_transaction do |txn|
      produce_message
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal "MessageBroker/Kafka/Topic/Produce/Named/#{@topic}", span[0]['name']
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}"
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}/Produce/#{@topic}"
  end

  def test_consume_creates_span_metrics
    produce_message
    harvest_span_events!

    consumer = config.consumer(group_id: 'ruby-test')
    consumer.subscribe(@topic)
    consumer.each_message do |message|
      # get 1 message and leave
      break
    end

    spans = harvest_span_events!
    span = spans[1][0]

    assert_equal "OtherTransaction/Message/Kafka/Topic/Consume/Named/#{@topic}", span[0]['name']
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}"
    assert_metrics_recorded "MessageBroker/Kafka/Nodes/#{host}/Consume/#{@topic}"
  end

  def test_rdkafka_distributed_tracing
    NewRelic::Agent.agent.stub :connected?, true do
      with_config(account_id: '190', primary_application_id: '46954', trusted_account_key: 'trust_this!') do
        in_transaction('first_txn_for_dt') do |txn|
          produce_message
        end
      end
      first_txn = harvest_transaction_events![1]

      consumer = config.consumer(group_id: 'ruby-test')
      consumer.subscribe(@topic)
      consumer.each_message do |message|
        # get 1 message and leave
        break
      end
      txn = harvest_transaction_events![1]

      assert_metrics_recorded 'Supportability/DistributedTrace/CreatePayload/Success'
      assert_equal txn[0][0]['traceId'], first_txn[0][0]['traceId']
      assert_equal txn[0][0]['parentId'], first_txn[0][0]['guid']
    end
  end

  def host
    '127.0.0.1:9092'
  end

  def config
    Kafka.new([host], client_id: 'ruby-test')
  end

  def produce_message(producer = config.producer)
    producer.produce(
      'Payload 1',
      topic: @topic,
      key: 'Key 1'
    )
    producer.deliver_messages
    producer.shutdown
  end
end