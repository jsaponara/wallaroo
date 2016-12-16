use "wallaroo/invariant"

class _CreditRequester
  let _pool: _CreditPool
  let _route: RouteLogic
  var _state: _CreditRequesterState = _UninitializedCreditRequester
  var _requesting: Bool = false

  let _us: Producer ref
  let _consumer: Consumer

  new create(producer: Producer ref, consumer: Consumer,
    pool: _CreditPool, route: RouteLogic)
   =>
    _us = producer
    _consumer = consumer
    _pool = pool
    _route = route
    pool.register_notify(_PerRouteCreditPoolNotify(_route, this))

  fun ref request() =>
    if not _requesting then
      _requesting = true

      ifdef "credit_trace" then
        @printf[I32](("--Route (%s %s): requesting credits. " +
          "Have %llu\n").cstring(),
          _state.desc().cstring(), _us.desc().cstring(),
          _pool.available())
      end
      _consumer.credit_request(_us)
    else
      ifdef "credit_trace" then
        @printf[I32](("----Route (%s %s): " +
          "Request already outstanding\n").cstring(),
        _state.desc().cstring(), _us.desc().cstring())
      end
    end

  fun ref receive(credits: ISize) =>
    ifdef debug then
      Invariant(credits > 0)
      _state.receive_preconditions(_pool)
    end

    ifdef "credit_trace" then
      @printf[I32](("-Route (%s %s): rcvd %llu credits." +
        " Had %llu out of %llu.\n").cstring(),
        _state.desc().cstring(), _us.desc().cstring(),
        credits,
        _pool.available(),
        _pool.max())
    end

    _requesting = false

    let started_from_zero = _pool.available() == 0
    let collected = _pool.collect(credits)
    _state.receive_action(this, started_from_zero)

  fun ref _credits_initialized() =>
    _state = _InitializedCreditRequester
    _route._credits_initialized()

  fun ref _credits_replenished() =>
    _route._credits_replenished()

interface _CreditRequesterState
  fun desc(): String
  fun ref receive_preconditions(pool: _CreditPool)
  fun ref receive_action(cr: _CreditRequester, was_zero: Bool)

class _UninitializedCreditRequester
  fun desc(): String =>
    "Uninitialized"

  fun ref receive_preconditions(pool: _CreditPool) =>
    Invariant(pool.available() == 0)

  fun ref receive_action(cr: _CreditRequester, was_zero: Bool) =>
    cr._credits_initialized()

class _InitializedCreditRequester
  fun desc(): String =>
    "Initialized"

  fun ref receive_preconditions(pool: _CreditPool) =>
    None

  fun ref receive_action(cr: _CreditRequester, was_zero: Bool) =>
    if was_zero then
      @printf[None]("Credits replenished\n".cstring())
      cr._credits_replenished()
    end
