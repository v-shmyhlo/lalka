# frozen_string_literal: true
require 'spec_helper'

# TODO: on_success called with wrong args
# TODO: on_error called with wrong args
# TODO: resolve called with wrong args
# TODO: reject called with wrong args
# TODO: error raised within fork
# TODO: error raised within on_success
# TODO: error raised within on_error

describe Lalka::Task do
  M = Dry::Monads
  Task = Lalka::Task

  def make_sync_task(success: nil, error: nil, &block)
    Task.new do |t|
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
    Task.new do |t|
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

  def wait_for_success(task)
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

  def try_task(async: true, delay_coef: 1, &block)
    if async
      make_async_task(delay_coef: delay_coef, &block)
    else
      make_sync_task(&block)
    end
  end

  def resolved_task(value = 'value', async: true, delay_coef: 1)
    if async
      make_async_task(success: value, delay_coef: delay_coef)
    else
      make_sync_task(success: value)
    end
  end

  def rejected_task(error = 'error', async: true, delay_coef: 1)
    if async
      make_async_task(error: error, delay_coef: delay_coef)
    else
      make_sync_task(error: error)
    end
  end

  define :match_error do |expected|
    match do |actual|
      expect(actual).to be_a(expected.class)
      expect(actual.message).to eq(expected.message)
    end
  end

  shared_examples 'it forks all tasks at the same time' do
    it 'resolves within reasonable time with #fork_wait' do
      actual = Benchmark.measure { task.fork_wait }.real
      expected = delay_time + delay_time * 0.2
      expect(actual).to be < expected
    end

    it 'resolves within reasonable time with #fork' do
      actual = Benchmark.measure { wait_for_success(task) }.real
      expected = delay_time + delay_time * 0.2
      expect(actual).to be < expected
    end
  end

  shared_examples 'it resolves to a value' do
    it 'resolves to correct value with #fork_wait' do
      expect(task.fork_wait).to eq(M.Right(value))
    end

    it 'resolves to correct value with #fork' do
      expect(wait_for_success(task)).to eq(value)
    end
  end

  shared_examples 'it rejects with an error' do
    it 'rejects with correct error with #fork_wait' do
      actual = task.fork_wait
      expect(actual).to be_left

      if actual.value.is_a?(StandardError)
        expect(actual.value).to match_error(error)
      else
        expect(actual.value).to eq(error)
      end
    end

    it 'rejects with correct error with #fork' do
      actual = wait_for_error(task)

      if actual.is_a?(StandardError)
        expect(actual).to match_error(error)
      else
        expect(actual).to eq(error)
      end
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
    describe '.new { |t| raise }' do
      let(:error) { RuntimeError.new('error') }

      it_behaves_like 'it rejects with an error' do
        let(:task) { Task.new { |t| raise 'error' } }
      end

      context 'when used in #ap' do
        it_behaves_like 'it rejects with an error' do
          let(:task) do
            f_task = resolved_task(-> (x) { x + 1 })
            v_task = Task.new { |t| raise 'error' }
            f_task.ap(v_task)
          end
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) do
            f_task = Task.new { |t| raise 'error' }
            v_task = resolved_task(99)
            f_task.ap(v_task)
          end
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) do
            task = Task.new { |t| raise 'error' }
            task.ap(task)
          end
        end
      end

      context 'when used in spaghetti :D' do
        it_behaves_like 'it rejects with an error' do
          let(:task) do
            f_task = resolved_task(98).bind do |x|
              resolved_task(-> (y) { x + y })
            end

            v_task = resolved_task(1).bind do |x|
              Task.new { |t| raise 'error' }
            end

            f_task.ap(v_task)
          end
        end
      end
    end

    describe '.new { |t| t.try { ... } }' do
      it 'resolves when no error raised' do
        task = try_task { 100 }
        result = task.fork_wait

        expect(result).to eq(M.Right(100))
      end

      it 'rejects when error raised' do
        task = try_task { raise 'error' }
        result = task.fork_wait

        expect(result.value).to match_error(RuntimeError.new('error'))
      end

      it 'resolves when no error raised' do
        task = try_task { 100 }
        expect(wait_for_success(task)).to eq(100)
      end

      it 'rejects when error raised' do
        task = try_task { raise 'error' }
        result = wait_for_error(task)

        expect(result).to match_error(RuntimeError.new('error'))
      end
    end

    describe '.resolve' do
      it_behaves_like 'it resolves to a value' do
        let(:task) { Task.resolve('value') }
        let(:value) { 'value' }
      end
    end

    describe '.reject' do
      it_behaves_like 'it rejects with an error' do
        let(:task) { Task.reject('error') }
        let(:error) { 'error' }
      end
    end

    describe '.try' do
      it 'resolves when no error raised' do
        task = try_task { 100 }
        result = task.fork_wait

        expect(result).to eq(M.Right(100))
      end

      it 'rejects when error raised' do
        task = try_task { raise 'error' }
        result = task.fork_wait

        expect(result.value).to match_error(RuntimeError.new('error'))
      end

      it 'resolves when no error raised' do
        task = try_task { 100 }
        expect(wait_for_success(task)).to eq(100)
      end

      it 'rejects when error raised' do
        task = try_task { raise 'error' }
        result = wait_for_error(task)

        expect(result).to match_error(RuntimeError.new('error'))
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
        result = wait_for_success(resolved_task)
        expect(result).to eq('value')
      end

      it 'executes on_error branch when rejected' do
        result = wait_for_error(rejected_task)
        expect(result).to eq('error')
      end

      it 'raises LocalJumpError when called without block' do
        expect { resolved_task.fork }.to raise_error(LocalJumpError)
      end

      it 'rejects with ArgumentError when on_success block is missing' do
        expect { resolved_task(async: false).fork { |t| t.on_error { |e| raise e } } }.to raise_error(ArgumentError, 'missing on_success block')
      end

      it 'raises ArgumentError when on_error block is missing' do
        expect { rejected_task(async: false).fork { |t| t.on_success { |v| v } } }.to raise_error(ArgumentError, 'missing on_error block')
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

      it 'rejects with ArgumentError when on_success block is missing' do
        result = resolved_task(async: false).fork_wait { |t| t.on_error { |e| e } }

        expect(result).to be_left
        expect(result.value).to match_error(ArgumentError.new('missing on_success block'))
      end

      it 'rejects with ArgumentError when on_error block is missing' do
        result = rejected_task(async: false).fork_wait { |t| t.on_success { |v| v } }

        expect(result).to be_left
        expect(result.value).to match_error(ArgumentError.new('missing on_error block'))
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
      let(:f) { -> (x) { x + '!' } }

      it 'raises ArgumentError when block and function passed' do
        expect { resolved_task.map(f, &f) }.to raise_error(ArgumentError, 'both block and function provided')
      end

      it 'raises ArgumentError when nothing passed' do
        expect { resolved_task.map }.to raise_error(ArgumentError, 'no block or function provided')
      end

      context 'when block passed' do
        it_behaves_like 'it resolves to a value' do
          let(:task) { resolved_task.map(&f) }
          let(:value) { 'value!' }
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task.map(&f) }
          let(:error) { 'error' }
        end
      end

      context 'when function passed' do
        it_behaves_like 'it resolves to a value' do
          let(:task) { resolved_task.map(f) }
          let(:value) { 'value!' }
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task.map(f) }
          let(:error) { 'error' }
        end
      end
    end

    describe '#bind' do
      let(:f) { -> (x) { Task.of(x + '!') } }

      it 'raises ArgumentError when block and function passed' do
        expect { resolved_task.bind(f, &f) }.to raise_error(ArgumentError, 'both block and function provided')
      end

      it 'raises ArgumentError when nothing passed' do
        expect { resolved_task.bind }.to raise_error(ArgumentError, 'no block or function provided')
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
        it_behaves_like 'it resolves to a value' do
          let(:task) { resolved_task(-> (x) { x + '!' }).ap(resolved_task) }
          let(:value) { 'value!' }
        end
      end

      describe 'rejected.ap(resolved)' do
        it_behaves_like 'it rejects with an error' do
          let(:task) { rejected_task('first_error').ap(resolved_task) }
          let(:error) { 'first_error' }
        end
      end

      describe 'resolved.ap(rejected)' do
        it_behaves_like 'it rejects with an error' do
          let(:task) { resolved_task(-> (x) { x + '!' }).ap(rejected_task('second_error')) }
          let(:error) { 'second_error' }
        end
      end

      describe 'rejected.ap(rejected)' do
        it_behaves_like 'it rejects with an error' do
          let(:task) do
            f_task = rejected_task('first_error')
            v_task = rejected_task('second_error', delay_coef: 2)

            f_task.ap(v_task)
          end

          let(:error) { 'first_error' }
        end

        it_behaves_like 'it rejects with an error' do
          let(:task) do
            f_task = rejected_task('first_error', delay_coef: 2)
            v_task = rejected_task('second_error')

            f_task.ap(v_task)
          end

          let(:error) { 'second_error' }
        end
      end

      describe 'pure(f).ap(resolved).ap(resolved)' do
        it_behaves_like 'it resolves to a value' do
          let(:task) do
            task1 = resolved_task(99)
            task2 = resolved_task(1)

            Task.of(-> (x, y) { x + y }.curry).ap(task1).ap(task2)
          end

          let(:value) { 100 }
        end
      end

      it_behaves_like 'it forks all tasks at the same time' do
        let(:task) do
          task1 = resolved_task(1)
          task2 = resolved_task(99)

          Task.of(-> (x, y) { x + y }.curry).ap(task1).ap(task2)
        end
      end

      it_behaves_like 'it forks all tasks at the same time' do
        let(:task) do
          task1 = resolved_task(1)
          task2 = resolved_task(99)

          Task.of(-> (x, y) { x + y }.curry).ap(task2).ap(task1)
        end
      end

      it_behaves_like 'it forks all tasks at the same time' do
        let(:task) do
          task1 = resolved_task(1)
          task2 = resolved_task(99)

          task1.map { |x| -> (y) { x + y } }.ap(task2)
        end
      end

      it_behaves_like 'it forks all tasks at the same time' do
        let(:task) do
          task1 = resolved_task(1)
          task2 = resolved_task(99)

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

        let(:task) { traverse(Task, [1, 2, 3, 4, 5]) { |v| resolved_task(v) } }

        it_behaves_like 'it resolves to a value' do
          let(:value) { [1, 2, 3, 4, 5] }
        end

        it_behaves_like 'it forks all tasks at the same time'
      end
    end
  end
end
