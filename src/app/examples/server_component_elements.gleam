import lustre/element.{type Element}
import lustre/attribute as attr
import lustre/server_component

pub fn pubsub_demo() -> ServerComponentElement {
  ServerComponentElement(
    route: "/ws/pubsub_demo",
  )
}

pub opaque type ServerComponentElement {
  ServerComponentElement(
    route: String,
  )
}

pub fn element(
  server_component_element sc: ServerComponentElement,
  attrs attrs: List(attr.Attribute(msg)),
  children children: List(Element(msg)),
) -> Element(msg) {
  server_component.element([
    server_component.route(sc.route),
    ..attrs
  ], children)
}

// fn route(
//   server_component sc: ServerComponent,
// ) -> String {
//   sc.route
// }
