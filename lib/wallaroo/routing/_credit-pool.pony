use "wallaroo/invariant"

class _CreditPool
  let _notify: _CreditPoolNotify
  let _max: ISize
  var _available: ISize
  var _refresh_at: ISize

  new create(notify: _CreditPoolNotify, start_at: ISize = 0,
    max: ISize = ISize.max_value())
  =>
    _notify = notify
    _available = start_at
    _max = max
    _refresh_at = _n(_available)

  fun available(): ISize =>
    _available

  fun next_refresh(): ISize =>
    _refresh_at

  fun ref collect(number: ISize = 1) =>
    ifdef debug then
      Invariant(number > 0)
    end

    _available = if (_available + number) > _max then
      let overflow = (_available + number) - _max
      _notify.overflowed(this, overflow)
      _max
    else
      _available + number
    end

    _refresh_at = _n(_available)

  fun ref expend() =>
    ifdef debug then
      Invariant(_available > 0)
    end

    _available = _available - 1
    if _available == 0 then
      _notify.exhausted(this)
    end
    if (_available == 0) or
      (_available == _refresh_at)
    then
      _notify.refresh_needed(this)
    end

  fun tag _n(n: ISize): ISize =>
    n - (n >> 2)

trait _CreditPoolNotify
  fun ref exhausted(pool: _CreditPool)
  fun ref refresh_needed(pool: _CreditPool)
  fun ref overflowed(pool: _CreditPool, amount: ISize)