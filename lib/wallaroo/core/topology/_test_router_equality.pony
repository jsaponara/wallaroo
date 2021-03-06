/*

Copyright 2017 The Wallaroo Authors.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 implied. See the License for the specific language governing
 permissions and limitations under the License.

*/

use "collections"
use "ponytest"
use "wallaroo_labs/equality"
use "wallaroo/core/boundary"
use "wallaroo/core/common"
use "wallaroo/ent/data_receiver"
use "wallaroo/ent/network"
use "wallaroo/ent/recovery"
use "wallaroo/ent/router_registry"
use "wallaroo/core/metrics"
use "wallaroo/core/routing"

actor _TestRouterEquality is TestList
  new make() =>
    None

  fun tag tests(test: PonyTest) =>
    test(_TestLocalPartitionRouterEquality)
    test(_TestOmniRouterEquality)
    test(_TestDataRouterEqualityAfterRemove)
    test(_TestDataRouterEqualityAfterAdd)
    test(_TestLatestAfterNew)
    test(_TestLatestWithoutNew)

class iso _TestLocalPartitionRouterEquality is UnitTest
  """
  Test that updating LocalPartitionRouter creates the expected changes

  Move step id 1 from worker w1 to worker w2.
  """
  fun name(): String =>
    "topology/LocalPartitionRouterEquality"

  fun ref apply(h: TestHelper) ? =>
    let auth = h.env.root as AmbientAuth
    let event_log = EventLog()
    let recovery_replayer = _RecoveryReplayerGenerator(h.env, auth)

    let step1 = _StepGenerator(event_log, recovery_replayer)
    let step2 = _StepGenerator(event_log, recovery_replayer)
    let step3 = _StepGenerator(event_log, recovery_replayer)
    let boundary2 = _BoundaryGenerator("w1", auth)
    let boundary3 = _BoundaryGenerator("w1", auth)

    let base_local_map = recover trn Map[U128, Step] end
    base_local_map(1) = step1
    let target_local_map: Map[U128, Step] val = recover Map[U128, Step] end

    let base_step_ids = recover trn Map[String, U128] end
    base_step_ids("k1") = 1
    base_step_ids("k2") = 2
    base_step_ids("k3") = 3
    let target_step_ids = recover trn Map[String, U128] end
    target_step_ids("k1") = 1
    target_step_ids("k2") = 2
    target_step_ids("k3") = 3

    let new_proxy_router = ProxyRouter("w1", boundary2,
      ProxyAddress("w2", 1), auth)

    let base_partition_routes = _BasePartitionRoutesGenerator(event_log, auth,
      step1, boundary2, boundary3)
    let target_partition_routes = _TargetPartitionRoutesGenerator(event_log, auth,
      new_proxy_router, boundary2, boundary3)

    var base_router: PartitionRouter =
      LocalPartitionRouter[String, String](consume base_local_map,
        consume base_step_ids, base_partition_routes,
      _PartitionFunctionGenerator(), _DefaultRouterGenerator())
    var target_router: PartitionRouter =
      LocalPartitionRouter[String, String](consume target_local_map,
        consume target_step_ids, target_partition_routes,
        _PartitionFunctionGenerator(), _DefaultRouterGenerator())
    h.assert_eq[Bool](false, base_router == target_router)

    base_router = base_router.update_route[String]("k1", new_proxy_router)?

    h.assert_eq[Bool](true, base_router == target_router)

class iso _TestOmniRouterEquality is UnitTest
  """
  Test that updating OmniRouter creates the expected changes

  Move step id 1 from worker w1 to worker w2.
  Move step id 2 from worker w2 to worker w1 (and point to step2)
  Add new boundary to worker 3
  """
  fun name(): String =>
    "topology/OmniRouterEquality"

  fun ref apply(h: TestHelper) ? =>
    let auth = h.env.root as AmbientAuth
    let event_log = EventLog()
    let recovery_replayer = _RecoveryReplayerGenerator(h.env, auth)

    let step1 = _StepGenerator(event_log, recovery_replayer)
    let step2 = _StepGenerator(event_log, recovery_replayer)

    let boundary2 = _BoundaryGenerator("w1", auth)
    let boundary3 = _BoundaryGenerator("w1", auth)

    let base_data_routes = recover trn Map[U128, Consumer] end
    base_data_routes(1) = step1

    let target_data_routes = recover trn Map[U128, Consumer] end
    target_data_routes(2) = step2

    let base_step_map = recover trn Map[U128, (ProxyAddress | U128)] end
    base_step_map(1) = ProxyAddress("w1", 1)
    base_step_map(2) = ProxyAddress("w2", 2)

    let target_step_map = recover trn Map[U128, (ProxyAddress | U128)] end
    target_step_map(1) = ProxyAddress("w2", 1)
    target_step_map(2) = ProxyAddress("w1", 2)

    let base_boundaries = recover trn Map[String, OutgoingBoundary] end
    base_boundaries("w2") = boundary2

    let target_boundaries = recover trn Map[String, OutgoingBoundary] end
    target_boundaries("w2") = boundary2
    target_boundaries("w3") = boundary3

    var base_router: OmniRouter = StepIdRouter("w1",
      consume base_data_routes, consume base_step_map,
      consume base_boundaries)

    let target_router: OmniRouter = StepIdRouter("w1",
      consume target_data_routes, consume target_step_map,
      consume target_boundaries)

    h.assert_eq[Bool](false, base_router == target_router)

    base_router = base_router.update_route_to_proxy(1, ProxyAddress("w2", 1))
    base_router = base_router.update_route_to_step(2, step2)
    base_router = base_router.add_boundary("w3", boundary3)

    h.assert_eq[Bool](true, base_router == target_router)

class iso _TestDataRouterEqualityAfterRemove is UnitTest
  """
  Test that updating DataRouter creates the expected changes

  Remove route to step id 2
  """
  fun name(): String =>
    "topology/DataRouterEqualityAfterRemove"

  fun ref apply(h: TestHelper) ? =>
    let auth = h.env.root as AmbientAuth
    let event_log = EventLog()
    let recovery_replayer = _RecoveryReplayerGenerator(h.env, auth)

    let step1 = _StepGenerator(event_log, recovery_replayer)
    let step2 = _StepGenerator(event_log, recovery_replayer)

    let base_routes = recover trn Map[U128, Consumer] end
    base_routes(1) = step1
    base_routes(2) = step2

    let target_routes = recover trn Map[U128, Consumer] end
    target_routes(1) = step1

    var base_router = DataRouter(consume base_routes)
    let target_router = DataRouter(consume target_routes)

    h.assert_eq[Bool](false, base_router == target_router)

    base_router = base_router.remove_route(2)

    h.assert_eq[Bool](true, base_router == target_router)

class iso _TestDataRouterEqualityAfterAdd is UnitTest
  """
  Test that updating DataRouter creates the expected changes

  Add route to step id 3
  """
  fun name(): String =>
    "topology/_TestDataRouterEqualityAfterAdd"

  fun ref apply(h: TestHelper) ? =>
    let auth = h.env.root as AmbientAuth
    let event_log = EventLog()
    let recovery_replayer = _RecoveryReplayerGenerator(h.env, auth)

    let step1 = _StepGenerator(event_log, recovery_replayer)
    let step2 = _StepGenerator(event_log, recovery_replayer)

    let base_routes = recover trn Map[U128, Consumer] end
    base_routes(1) = step1

    let target_routes = recover trn Map[U128, Consumer] end
    target_routes(1) = step1
    target_routes(2) = step2

    var base_router = DataRouter(consume base_routes)
    let target_router = DataRouter(consume target_routes)

    h.assert_eq[Bool](false, base_router == target_router)

    base_router = base_router.add_route(2, step2)

    h.assert_eq[Bool](true, base_router == target_router)

primitive _BasePartitionRoutesGenerator
  fun apply(event_log: EventLog, auth: AmbientAuth, step1: Step,
    boundary2: OutgoingBoundary, boundary3: OutgoingBoundary):
    Map[String, (Step | ProxyRouter)] val
  =>
    let m = recover trn Map[String, (Step | ProxyRouter)] end
    m("k1") = step1
    m("k2") = ProxyRouter("w1", boundary2,
      ProxyAddress("w2", 2), auth)
    m("k3") = ProxyRouter("w1", boundary3,
      ProxyAddress("w3", 3), auth)
    consume m

primitive _TargetPartitionRoutesGenerator
  fun apply(event_log: EventLog, auth: AmbientAuth,
    new_proxy_router: ProxyRouter, boundary2: OutgoingBoundary,
    boundary3: OutgoingBoundary): Map[String, (Step | ProxyRouter)] val
  =>
    let m = recover trn Map[String, (Step | ProxyRouter)] end
    m("k1") = new_proxy_router
    m("k2") = ProxyRouter("w1", boundary2,
      ProxyAddress("w2", 2), auth)
    m("k3") = ProxyRouter("w1", boundary3,
      ProxyAddress("w3", 3), auth)
    consume m

primitive _LocalMapGenerator
  fun apply(): Map[U128, Step] val =>
    recover Map[U128, Step] end

primitive _StepIdsGenerator
  fun apply(): Map[String, U128] val =>
    recover Map[String, U128] end

primitive _PartitionFunctionGenerator
  fun apply(): PartitionFunction[String, String] val =>
    {(s: String): String => s}

primitive _DefaultRouterGenerator
  fun apply(): (Router | None) =>
    None

primitive _StepGenerator
  fun apply(event_log: EventLog, recovery_replayer: RecoveryReplayer): Step =>
    Step(RouterRunner, MetricsReporter("", "", _NullMetricsSink),
      1, BoundaryOnlyRouteBuilder, event_log, recovery_replayer,
      recover Map[String, OutgoingBoundary] end)

primitive _BoundaryGenerator
  fun apply(worker_name: String, auth: AmbientAuth): OutgoingBoundary =>
    OutgoingBoundary(auth, worker_name,
      MetricsReporter("", "", _NullMetricsSink), "", "")

primitive _RouterRegistryGenerator
  fun apply(env: Env, auth: AmbientAuth): RouterRegistry =>
    RouterRegistry(auth, "", _DataReceiversGenerator(env, auth),
      _ConnectionsGenerator(env, auth), 0)

primitive _DataReceiversGenerator
  fun apply(env: Env, auth: AmbientAuth): DataReceivers =>
    DataReceivers(auth, _ConnectionsGenerator(env, auth), "")

primitive _ConnectionsGenerator
  fun apply(env: Env, auth: AmbientAuth): Connections =>
    Connections("", "", auth, "", "", "", "", "", "", "", "",
      _NullMetricsSink, "", "", false, "", false
      where event_log = EventLog())

primitive _RecoveryReplayerGenerator
  fun apply(env: Env, auth: AmbientAuth): RecoveryReplayer =>
    RecoveryReplayer(auth, "", _DataReceiversGenerator(env, auth),
      _RouterRegistryGenerator(env, auth), _Cluster)

actor _Cluster is Cluster
  be notify_cluster_of_new_stateful_step[K: (Hashable val & Equatable[K] val)](
    id: U128, key: K, state_name: String, exclusions: Array[String] val =
    recover Array[String] end)
  =>
    None

actor _NullMetricsSink
  be send_metrics(metrics: MetricDataList val) =>
    None

  fun ref set_nodelay(state: Bool) =>
    None

  be writev(data: ByteSeqIter) =>
    None

  be dispose() =>
    None
