# frozen_string_literal: true
require 'spec_helper'
require 'benchmark'
require 'pry'

describe Lalka do
  it 'has a version number' do
    expect(Lalka::VERSION).not_to be nil
  end

  describe Lalka::Task do
    M = Dry::Monads

    def delay(time = 0.1, &block)
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

    let(:queue) { Queue.new }

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
      describe '.new { |t| t.try { ... } }' do
        def try_task
          Lalka::Task.new do |t|
            delay { t.try { yield } }
          end
        end

        it 'resolves when no error raised' do
          task = try_task { 100 }
          result = task.fork_wait

          expect(result).to eq(M.Right(100))
        end

        it 'rejects when error raised' do
          task = try_task { raise 'error' }
          result = task.fork_wait

          expect(result.value).to be_a(RuntimeError)
          expect(result.value.message).to eq('error')
        end

        it 'resolves when no error raised' do
          task = try_task { 100 }
          task.fork { |t| t.on_success { |v| queue.push v } }

          expect(queue.pop).to eq(100)
        end

        it 'rejects when error raised' do
          task = try_task { raise 'error' }
          task.fork { |t| t.on_error { |v| queue.push v } }

          result = queue.pop
          expect(result).to be_a(RuntimeError)
          expect(result.message).to eq('error')
        end
      end

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

      describe '.try' do
        def try_task
          Lalka::Task.try { yield }
        end

        it 'resolves when no error raised' do
          task = try_task { 100 }
          result = task.fork_wait

          expect(result).to eq(M.Right(100))
        end

        it 'rejects when error raised' do
          task = try_task { raise 'error' }
          result = task.fork_wait

          expect(result.value).to be_a(RuntimeError)
          expect(result.value.message).to eq('error')
        end

        it 'resolves when no error raised' do
          task = try_task { 100 }
          task.fork { |t| t.on_success { |v| queue.push v } }

          expect(queue.pop).to eq(100)
        end

        it 'rejects when error raised' do
          task = try_task { raise 'error' }
          task.fork { |t| t.on_error { |v| queue.push v } }

          result = queue.pop
          expect(result).to be_a(RuntimeError)
          expect(result.message).to eq('error')
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
          resolved_task.fork do |t|
            t.on_success do |error|
              queue.push(error)
            end
          end

          expect(queue.pop).to eq('value')
        end

        it 'when rejected executes on_error branch' do
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

        context 'without block' do
          it 'when resolved returns Right' do
            result = resolved_task.fork_wait
            expect(result).to eq(M.Right('value'))
          end

          it 'when rejected returns Left' do
            result = rejected_task.fork_wait
            expect(result).to eq(M.Left('error'))
          end
        end
      end

      describe '#map' do
        let(:mapper) { -> (value) { value + '!' } }

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

          it 'is chainable' do
            task1 = Lalka::Task.resolve(99)
            task2 = Lalka::Task.resolve(1)
            task3 = Lalka::Task.of(-> (x, y) { x + y }.curry).ap(task1).ap(task2)
            result = task3.fork_wait

            expect(result).to eq(M.Right(100))
          end

          it 'forks both tasks at the same time' do
            task1 = resolved_task(1, 1)
            task2 = resolved_task(99, 1)

            task3 = Lalka::Task.of(-> (x, y) { x + y }.curry).ap(task1).ap(task2)
            real = Benchmark.measure { task3.fork_wait }.real

            expect(real).to be < 1.1
          end

          it 'forks both tasks at the same time' do
            task1 = resolved_task(1, 1)
            task2 = resolved_task(99, 1)

            task3 = Lalka::Task.of(-> (x, y) { x + y }.curry).ap(task2).ap(task1)
            real = Benchmark.measure { task3.fork_wait }.real

            expect(real).to be < 1.1
          end

          it 'forks both tasks at the same time' do
            task1 = resolved_task(1, 1)
            task2 = resolved_task(99, 1)

            task3 = task1.map { |x| -> (y) { x + y } }.ap(task2)
            real = Benchmark.measure { task3.fork_wait }.real

            expect(real).to be < 1.1
          end

          it 'forks both tasks at the same time' do
            task1 = resolved_task(1, 1)
            task2 = resolved_task(99, 1)

            task3 = task2.map { |x| -> (y) { x + y } }.ap(task1)
            real = Benchmark.measure { task3.fork_wait }.real

            expect(real).to be < 1.1
          end
        end
      end
    end
  end
end
