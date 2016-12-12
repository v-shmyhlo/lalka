# frozen_string_literal: true
require 'spec_helper'

describe Lalka do
  it 'has a version number' do
    expect(Lalka::VERSION).not_to be nil
  end

  describe Lalka::Task do
    M = Dry::Monads

    def delay(time, &block)
      Thread.new(block) do |block|
        sleep time
        block.call
      end
    end

    def resolved_task(value = 'value', delay_time = 0.1)
      Lalka::Task.new do |t|
        delay(delay_time) { t.resolve(value) }
      end
    end

    def rejected_task(error = 'error', delay_time = 0.1)
      Lalka::Task.new do |t|
        delay(delay_time) { t.reject(error) }
      end
    end

    let(:handler) do
      lambda do |t|
        t.on_error do |e|
          'Error: ' + e
        end

        t.on_success do |v|
          'Success: ' + v
        end
      end
    end

    describe 'Class Methods' do
      describe '.resolve' do
        it 'creates resolved' do
          task = Lalka::Task.resolve('value')
          result = task.fork_wait(&handler)

          expect(result).to eq(M.Right('Success: value'))
        end
      end

      describe '.reject' do
        it 'creates rejected' do
          task = Lalka::Task.reject('error')
          result = task.fork_wait(&handler)

          expect(result).to eq(M.Left('Error: error'))
        end
      end
    end

    describe 'Instance Method' do
      describe '#fork' do
        it 'when resolved returns nil' do
          result = resolved_task.fork(&handler)
          expect(result).to be_nil
        end

        it 'when rejected returns nil' do
          result = rejected_task.fork(&handler)
          expect(result).to be_nil
        end

        it 'when rejected executes on_success branch' do
          queue = Queue.new

          resolved_task.fork do |t|
            t.on_success do |error|
              queue.push(error)
            end
          end

          expect(queue.pop).to eq('value')
        end

        it 'when rejected executes on_error branch' do
          queue = Queue.new

          rejected_task.fork do |t|
            t.on_error do |error|
              queue.push(error)
            end
          end

          expect(queue.pop).to eq('error')
        end
      end

      describe '#fork_wait' do
        it 'when resolved returns Right' do
          result = resolved_task.fork_wait(&handler)
          expect(result).to eq(M.Right('Success: value'))
        end

        it 'when rejected returns Left' do
          result = rejected_task.fork_wait(&handler)
          expect(result).to eq(M.Left('Error: error'))
        end
      end

      describe '#map' do
        let(:mapper) { -> value { value + '!' } }

        it 'when resolved returns mapped Right' do
          result = resolved_task.map(&mapper).fork_wait(&handler)
          expect(result).to eq(M.Right('Success: value!'))
        end

        it 'when rejected returns unchanged Left' do
          result = rejected_task.map(&mapper).fork_wait(&handler)
          expect(result).to eq(M.Left('Error: error'))
        end
      end

      describe '#bind' do
        describe 'resolved.bind(x -> resolved)' do
          it 'chains computations' do
            task = resolved_task.bind { |v| resolved_task(v + '!') }
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Right('Success: value!'))
          end
        end

        describe 'rejected.bind(x -> resolved)' do
          it 'returns first error' do
            task = rejected_task('first_error').bind { |v| resolved_task(v + '!') }
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: first_error'))
          end
        end

        describe 'resolved.bind(x -> rejected)' do
          it 'returns second error' do
            task = resolved_task.bind { |v| rejected_task('Error: second_error (but has value: ' + v + ')') }
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: Error: second_error (but has value: value)'))
          end
        end

        describe 'rejected.bind(x -> rejected)' do
          it 'returns first error' do
            task = rejected_task('first_error').bind { |v| rejected_task('Error: second_error (but has value: ' + v + ')') }
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: first_error'))
          end
        end
      end

      describe '#ap' do
        describe 'resolved.ap(resolved)' do
          it 'chains computations' do
            task = resolved_task(-> (value) { value + '!' }).ap(resolved_task)
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Right('Success: value!'))
          end
        end

        describe 'rejected.ap(resolved)' do
          it 'returns first error' do
            task = rejected_task('first_error').ap(resolved_task)
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: first_error'))
          end
        end

        describe 'resolved.ap(rejected)' do
          it 'returns second error' do
            task = resolved_task(-> (value) { value + '!' }).ap(rejected_task('second_error'))
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: second_error'))
          end
        end

        describe 'rejected.ap(rejected)' do
          it 'returns first error' do
            task = rejected_task('first_error', 0.1).ap(rejected_task('second_error', 0.2))
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: first_error'))
          end

          it 'returns second error' do
            task = rejected_task('first_error', 0.2).ap(rejected_task('second_error', 0.1))
            result = task.fork_wait(&handler)
            expect(result).to eq(M.Left('Error: second_error'))
          end
        end
      end
    end
  end
end
