import tables, strutils, options

type
  Callback = proc(): void
  StateEvent[S,E] = tuple[state: S, event: E]
  Transition[S] = tuple[nexState: S, action: Option[Callback]]

  Machine*[S,E] =  ref object of RootObj
    initialState: S
    currentState: Option[S]
    transitions: TableRef[StateEvent[S,E], Transition[S]]
    transitionsAny: TableRef[S, Transition[S]]
    defaultTransition: Option[Transition[S]]

  TransitionNotFoundException* = object of Exception

proc reset*(m: Machine) =
  m.currentState = some(m.initialState)

proc setInitialState*[S,E](m: Machine[S,E], state: S) =
  m.initialState = state
  if m.currentState.isNone:
    m.reset()

proc newMachine*[S,E](initialState: S): Machine[S,E] =
  result = new(Machine[S,E])
  result.transitions = newTable[StateEvent[S,E], Transition[S]]()
  result.transitionsAny = newTable[S, Transition[S]]()
  result.setInitialState(initialState)

proc addTransitionAny*[S,E](m: Machine[S,E], state: S, nextState: S) =
  m.transitionsAny[state] = (nextState, none(Callback))

proc addTransitionAny*[S,E](m: Machine[S,E], state, nextState: S, action: Callback) =
  m.transitionsAny[state] = (nextState, some(action))

proc addTransition*[S,E](m: Machine[S,E], state: S, event: E, nextState: S) =
  m.transitions[(state, event)] = (nextState, none(Callback))

proc addTransition*[S,E](m: Machine[S,E], state: S, event: E, nextState: S, action: Callback) =
  m.transitions[(state, event)] = (nextState, some(action))

proc setDefaultTransition*[S,E](m: Machine[S,E], state: S) =
  m.defaultTransition = some((state, none(Callback)))

proc setDefaultTransition*[S,E](m: Machine[S,E], state: S, action: Callback) =
  m.defaultTransition = some((state, some(action)))

proc getTransition*[S,E](m: Machine[S,E], event: E, state: S): Transition[S] =
  let map = (state, event)
  if m.transitions.hasKey(map):
    result = m.transitions[map]
  elif m.transitionsAny.hasKey(state):
    result = m.transitionsAny[state]
  elif m.defaultTransition.isSome:
    result = m.defaultTransition.get
  else: raise newException(TransitionNotFoundException, "Transition is not defined: Event($#) State($#)" % [$event, $state])

proc getCurrentState*(m: Machine): auto =
  m.currentState.get

proc process*[S,E](m: Machine[S,E], event: E) =
  let transition = m.getTransition(event, m.currentState.get)
  if transition[1].isSome:
    get(transition[1])()
  m.currentState = some(transition[0])
  #echo event, " ", m.currentState.get


when isMainModule:
  proc cb() =
    echo "i'm evaporating"

  type
    State = enum
      SOLID
      LIQUID
      GAS
      PLASMA

    Event = enum
      MELT
      EVAPORATE
      SUBLIMATE
      IONIZE

  var m = newMachine[State, Event](LIQUID)
  #m.setDefaultTransition()
  m.addTransition(SOLID, MELT, LIQUID)
  m.addTransition(LIQUID, EVAPORATE, GAS, cb)
  m.addTransition(SOLID, SUBLIMATE, GAS)
  m.addTransition(GAS, IONIZE, PLASMA)
  m.addTransition(SOLID, MELT, LIQUID)

  assert m.getCurrentState() == LIQUID
  m.process(EVAPORATE)
  assert m.getCurrentState() == GAS
  m.process(IONIZE)
  assert m.getCurrentState() == PLASMA
