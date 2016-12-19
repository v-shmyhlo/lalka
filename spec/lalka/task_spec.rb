# frozen_string_literal: true
require 'spec_helper'

describe Lalka::Task do
  M = Dry::Monads

  def make_sync_task(success: nil, error: nil, &block)
    Lalka::Task.new do |t|
      if !success.nil?
        t.resolve(success)
      elsif !error.nil?
        t.reject(error)
      elsif block_given?
        t.try(&block)
      else
        raise ArgumentError
      end
    end
  end

  def make_async_task(success: nil, error: nil, delay_coef: 1, &block)
    Lalka::Task.new do |t|
      delay(delay_coef) do
        if !success.nil?
          t.resolve(success)
        elsif !error.nil?
          t.reject(error)
        elsif block_given?
          t.try(&block)
        else
          raise ArgumentError
        end
      end
    end
  end

  def wait_for_sucess(task)
    queue = Queue.new

    task.fork do |t|
      t.on_success { |v| queue.push(v) }
    end

    queue.pop
  end

  def wait_for_error(task)
    queue = Queue.new

    task.fork do |t|
      t.on_error { |e| queue.push(e) }
    end

    queue.pop
  end

  def delay(coef = 1, &block)
    time = delay_time * coef

    Thread.new(block) do |block|
      sleep time
      block.call
    end
  end

  def resolved_task(value = 'value')
    make_async_task(success: value)
  end

  def rejected_task(error = 'error')
    make_async_task(error: error)
  end

  shared_examples 'it forks all tasks at the same time' do
    it 'resolves within reasonable time with #fork_wait' do
      actual = Benchmark.measure { task.fork_wait }.real
      expected = delay_time + delay_time * 0.2
      expect(actual).to be < expected
    end

    it 'resolves within reasonable time with #fork' do
      actual = Benchmark.measure { wait_for_sucess(task) }.real
      expected = delay_time + delay_time * 0.2
      expect(actual).to be < expected
    end
  end

  shared_examples 'it resolves to a value' do
    it 'resolves to correct value with #fork_wait' do
      expect(task.fork_wait).to eq(M.Right(value))
    end

    it 'resolves to correct value with #fork' do
      expect(wait_for_sucess(task)).to eq(value)
    end
  end

  shared_examples 'it rejects with an error' do
    it 'rejects with correct error with #fork_wait' do
      expect(task.fork_wait).to eq(M.Left(error))
    end

    it 'rejects with correct error with #fork' do
      expect(wait_for_error(task)).to eq(error)
    end
  end

  let(:delay_time) { 0.1 }

  let(:handler) do
    lambda do |t|
      t.on_success do |v|
        'Success: ' + v
      end

      t.on_error do |e|
        'Error: ' + e
      end
    end
  end

  describe 'Class Methods' do
    describe '.new { |t| t.try { ... } }' do
      it 'resolves when no error raised' do
        task = make_async_task { 100 }
        result = task.fork_wait

        expect(result).to eq(M.Right(100))
      end

      it 'rejects when error raised' do
        task = make_async_task { raise 'error' }
        result = task.fork_wait

        expect(result.value).to be_a(RuntimeError)
        expect(result.value.message).to eq('error')
      end

      it 'resolves when no error raised' do
        task = make_async_task { 100 }
        expect(wait_for_sucess(task)).to eq(100)
      end

      it 'rejects when error raised' do
        task = make_async_task { raise 'error' }
        result = wait_for_error(task)

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
      it 'resolves when no error raised' do
        task = make_sync_task { 100 }
        result = task.fork_wait

        expect(result).to eq(M.Right(100))
      end

      it 'rejects when error raised' do
        task = make_sync_task { raise 'error' }
        result = task.fork_wait

        expect(result.value).to be_a(RuntimeError)
        expect(result.value.message).to eq('error')
      end

      it 'resolves when no error raised' do
        task = make_sync_task { 100 }
        expect(wait_for_sucess(task)).to eq(100)
      end

      it 'rejects when error raised' do
        task = make_sync_task { raise 'error' }
        result = wait_for_error(task)
        expect(result).to be_a(RuntimeError)
        expect(result.message).to eq('error')
      end
    end
  end

  describe 'Instance Method' do
    describe '#fork' do
      it 'returns nil when resolved' do
        result = resolved_task.fork(&handler)
        expect(result).to be_nil
      end

      it 'returns nil when rejected' do
        result = rejected_task.fork(&handler)
        expect(result).to be_nil
      end

      it 'executes on_success branch when rejected' do
        result = wait_for_sucess(resolved_task)
        expect(result).to eq('value')
      end

      it 'executes on_error branch when rejected' do
        result = wait_for_error(rejected_task)
        expect(result).to eq('error')
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

      it 'raises ArgumentError when block and function passed' do
        expect { resolved_task.map(mapper, &mapper) }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError when nothing passed' do
        expect { resolved_task.map }.to raise_error(ArgumentError)
      end

      context 'when block passed' do
        it_behaves_like 'it resolves to a value' do
          let(:task) { resolved_task.map(&mapper) }
          let(:value) { 'value!' }
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task.map(&mapper) }
          let(:error) { 'error' }
        end
      end

      context 'when function passed' do
        it_behaves_like 'it resolves to a value' do
          let(:task) { resolved_task.map(mapper) }
          let(:value) { 'value!' }
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task.map(mapper) }
          let(:error) { 'error' }
        end
      end
    end

    describe '#bind' do
      xit 'raises ArgumentError when block and function passed' do
        expect { resolved_task.bind(mapper, &mapper) }.to raise_error(ArgumentError)
      end

      xit 'raises ArgumentError when nothing passed' do
        expect { resolved_task.bind }.to raise_error(ArgumentError)
      end

      describe 'resolved.bind(x -> resolved)' do
        it_behaves_like 'it resolves to a value' do
          let(:task) { resolved_task.bind { |v| resolved_task(v + '!') } }
          let(:value) { 'value!' }
        end
      end

      describe 'rejected.bind(x -> resolved)' do
        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task('first_error').bind { |v| resolved_task(v + '!') } }
          let(:error) { 'first_error' }
        end
      end

      describe 'resolved.bind(x -> rejected)' do
        it_behaves_like 'it rejects with an error' do
          let(:task) { resolved_task.bind { |v| rejected_task('second_error (but has value: ' + v + ')') } }
          let(:error) { 'second_error (but has value: value)' }
        end
      end

      describe 'rejected.bind(x -> rejected)' do
        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task('first_error').bind { |v| rejected_task('second_error (but has value: ' + v + ')') } }
          let(:error) { 'first_error' }
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
          f_task = make_async_task(error: 'first_error')
          v_task = make_async_task(error: 'second_error', delay_coef: 2)

          task = f_task.ap(v_task)
          result = task.fork_wait(&handler)

          expect(result).to eq(M.Left('Error: first_error'))
        end

        it 'returns second error' do
          f_task = make_async_task(error: 'first_error', delay_coef: 2)
          v_task = make_async_task(error: 'second_error')

          task = f_task.ap(v_task)
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

        it_behaves_like 'it forks all tasks at the same time' do
          let(:task) do
            task1 = make_async_task(success: 1)
            task2 = make_async_task(success: 99)

            Lalka::Task.of(-> (x, y) { x + y }.curry).ap(task1).ap(task2)
          end
        end

        it_behaves_like 'it forks all tasks at the same time' do
          let(:task) do
            task1 = make_async_task(success: 1)
            task2 = make_async_task(success: 99)

            Lalka::Task.of(-> (x, y) { x + y }.curry).ap(task2).ap(task1)
          end
        end

        it_behaves_like 'it forks all tasks at the same time' do
          let(:task) do
            task1 = make_async_task(success: 1)
            task2 = make_async_task(success: 99)

            task1.map { |x| -> (y) { x + y } }.ap(task2)
          end
        end

        it_behaves_like 'it forks all tasks at the same time' do
          let(:task) do
            task1 = make_async_task(success: 1)
            task2 = make_async_task(success: 99)

            task2.map { |x| -> (y) { x + y } }.ap(task1)
          end
        end

        context 'when used in traverse' do
          def traverse(type, xs)
            cons = -> (x, xs) { [x, *xs] }.curry

            xs.reverse.reduce(type.of([])) do |acc, value|
              type.of(cons).ap(yield(value)).ap(acc)
            end
          end

          let(:task) { traverse(Lalka::Task, [1, 2, 3, 4, 5]) { |v| make_async_task(success: v) } }

          it_behaves_like 'it resolves to a value' do
            let(:value) { [1, 2, 3, 4, 5] }
          end

          it_behaves_like 'it forks all tasks at the same time'
        end
      end
    end
  end
end
