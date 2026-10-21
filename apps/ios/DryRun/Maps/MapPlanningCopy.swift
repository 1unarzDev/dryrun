import Foundation

/// Authored interface copy kept in the map module until the shared locale catalog is next revised.
enum MapPlanningCopy {
    static func text(_ key: String, locale: String) -> String {
        let table = locale == "es" ? spanish : locale == "vi" ? vietnamese : english
        return table[key] ?? english[key] ?? key
    }
    private static let english = [
        "ordinary": "Review ordinary travel separately from local emergency instructions.",
        "details": "Planning context",
        "structureFire": "Use the indoor escape plan and outdoor gathering point. Street directions do not replace leaving the building.",
        "structureFireAdvance": "Plan indoor exits and an outdoor gathering point before a fire.",
        "tornadoShelter": "Use the appropriate shelter and assistance plan for this household. Street directions do not replace reaching shelter.",
        "tornadoShelterAdvance": "Arrange access and any transport to appropriate shelter before a warning. Ordinary directions can help with advance planning.",
        "flashFlood": "Compare preparations before access closes. Avoid floodwater on foot and in vehicles. Ordinary directions do not establish passable roads; follow current local instructions.",
        "hurricaneAdvance": "Check the local evacuation zone, timing, destination and transport before a storm.",
        "freezeContinuity": "Plan warmth, power continuity and assistance; leaving home is not the default.",
        "heatContinuity": "Plan access to cooling and power continuity, including how to reach confirmed help.",
        "waterContinuity": "Plan a usable water source and how to collect it; a listing does not confirm availability.",
        "simulation": "Simulation conditions are practice inputs. Map directions show ordinary travel, not simulated or verified safe roads.",
        "plannedExit": "Planned indoor exit",
        "missingGathering": "Choose an outdoor gathering point for this home before practice.",
        "homeMarker": "This links planned indoor egress to the gathering point. It does not confirm anyone arrived outside. The home pin does not locate a particular door.",
        "reviewExit": "Review the current indoor route and exterior exit in the home plan before linking an outdoor gathering point.",
        "hurricaneUnknown": "No locally supported evacuation plan is recorded. Confirm the applicable zone and instructions with the local authority before choosing travel.",
        "hurricaneReview": "The saved hurricane plan needs source, location or date review. Its directions are not shown as current official guidance.",
        "officialPlan": "Recorded official planning information",
        "zone": "Evacuation zone",
        "officialBoundary": "This saved plan is not a current evacuation order. Open the source for current instructions. Apple directions remain ordinary travel estimates.",
        "noCar": "No household vehicle is recorded. Arrange and confirm suitable transport and assistance in advance.",
        "confirmTransport": "Confirm the chosen transport, accessibility and departure timing against local instructions."
    ]
    private static let spanish = [
        "ordinary": "Revise el viaje habitual por separado de las instrucciones locales de emergencia.",
        "details": "Contexto del plan",
        "structureFire": "Use el plan de salida interior y el punto de reunión exterior. Las rutas de calle no sustituyen salir del edificio.",
        "structureFireAdvance": "Planifique las salidas interiores y un punto de reunión exterior antes de un incendio.",
        "tornadoShelter": "Use el refugio y el plan de asistencia adecuados para este hogar. Las rutas de calle no sustituyen llegar al refugio.",
        "tornadoShelterAdvance": "Organice el acceso y el transporte a un refugio adecuado antes de una advertencia. Las rutas habituales ayudan a planificar con antelación.",
        "flashFlood": "Compare preparativos antes de que se cierre el acceso. Evite el agua de inundación a pie y en vehículos. Las rutas habituales no confirman vías transitables; siga las instrucciones locales actuales.",
        "hurricaneAdvance": "Compruebe la zona de evacuación local, el horario, el destino y el transporte antes de una tormenta.",
        "freezeContinuity": "Planifique abrigo, continuidad eléctrica y asistencia; salir de casa no es la opción predeterminada.",
        "heatContinuity": "Planifique el acceso a refrigeración y electricidad, incluido cómo llegar a ayuda confirmada.",
        "waterContinuity": "Planifique una fuente de agua utilizable y cómo recogerla; un anuncio no confirma disponibilidad.",
        "simulation": "Las condiciones simuladas son para practicar. Las rutas muestran viajes habituales, no vías simuladas ni de seguridad verificada.",
        "plannedExit": "Salida interior planificada",
        "missingGathering": "Elija un punto de reunión exterior para este hogar antes de practicar.",
        "homeMarker": "Esto vincula la salida interior planificada con el punto de reunión. No confirma que alguien haya llegado al exterior. El marcador de casa no ubica una puerta concreta.",
        "reviewExit": "Revise la ruta interior actual y la salida exterior en el plano antes de vincular un punto de reunión.",
        "hurricaneUnknown": "No hay un plan de evacuación local respaldado. Confirme la zona y las instrucciones con la autoridad local antes de elegir el viaje.",
        "hurricaneReview": "El plan de huracán guardado necesita revisar su fuente, ubicación o fecha. Sus indicaciones no se muestran como instrucciones oficiales actuales.",
        "officialPlan": "Información oficial de planificación guardada",
        "zone": "Zona de evacuación",
        "officialBoundary": "Este plan guardado no es una orden de evacuación actual. Abra la fuente para ver instrucciones actuales. Las rutas de Apple siguen siendo estimaciones de viaje habitual.",
        "noCar": "No hay un vehículo registrado en el hogar. Organice y confirme transporte y asistencia adecuados con antelación.",
        "confirmTransport": "Confirme el transporte elegido, la accesibilidad y la hora de salida según las instrucciones locales."
    ]
    private static let vietnamese = [
        "ordinary": "Xem riêng việc đi lại thông thường và hướng dẫn khẩn cấp tại địa phương.",
        "details": "Bối cảnh kế hoạch",
        "structureFire": "Dùng kế hoạch thoát trong nhà và điểm tập trung ngoài trời. Chỉ đường ngoài phố không thay thế việc ra khỏi tòa nhà.",
        "structureFireAdvance": "Lập kế hoạch lối thoát trong nhà và điểm tập trung ngoài trời trước khi có cháy.",
        "tornadoShelter": "Dùng nơi trú và kế hoạch hỗ trợ phù hợp với gia đình. Chỉ đường ngoài phố không thay thế việc đến nơi trú.",
        "tornadoShelterAdvance": "Sắp xếp lối tiếp cận và phương tiện đến nơi trú phù hợp trước khi có cảnh báo. Chỉ đường thông thường giúp chuẩn bị trước.",
        "flashFlood": "So sánh cách chuẩn bị trước khi lối đi bị đóng. Tránh nước lũ khi đi bộ và đi xe. Chỉ đường thông thường không xác nhận đường còn đi được; hãy theo hướng dẫn hiện hành tại địa phương.",
        "hurricaneAdvance": "Kiểm tra vùng sơ tán địa phương, thời gian, điểm đến và phương tiện trước cơn bão.",
        "freezeContinuity": "Lập kế hoạch giữ ấm, duy trì điện và hỗ trợ; không mặc định phải rời nhà.",
        "heatContinuity": "Lập kế hoạch tiếp cận nơi làm mát và duy trì điện, gồm cách đến nơi hỗ trợ đã xác nhận.",
        "waterContinuity": "Lập kế hoạch nguồn nước dùng được và cách lấy nước; danh sách địa điểm không xác nhận còn nước.",
        "simulation": "Điều kiện mô phỏng dùng để luyện tập. Chỉ đường thể hiện đi lại thông thường, không phải đường mô phỏng hay đã xác minh an toàn.",
        "plannedExit": "Lối thoát trong nhà dự kiến",
        "missingGathering": "Chọn điểm tập trung ngoài trời cho nhà này trước khi luyện tập.",
        "homeMarker": "Phần này nối kế hoạch thoát trong nhà với điểm tập trung. Không xác nhận ai đã ra ngoài. Ghim nhà không xác định vị trí một cửa cụ thể.",
        "reviewExit": "Xem lại tuyến trong nhà và lối ra ngoài hiện tại trên sơ đồ trước khi nối với điểm tập trung.",
        "hurricaneUnknown": "Chưa lưu kế hoạch sơ tán có nguồn địa phương hỗ trợ. Xác nhận vùng và hướng dẫn với cơ quan địa phương trước khi chọn cách đi.",
        "hurricaneReview": "Kế hoạch bão đã lưu cần kiểm tra nguồn, vị trí hoặc ngày. Hướng dẫn này không được hiển thị như chỉ dẫn chính thức hiện hành.",
        "officialPlan": "Thông tin lập kế hoạch chính thức đã lưu",
        "zone": "Vùng sơ tán",
        "officialBoundary": "Kế hoạch đã lưu không phải lệnh sơ tán hiện hành. Mở nguồn để xem hướng dẫn mới nhất. Chỉ đường Apple vẫn là ước tính đi lại thông thường.",
        "noCar": "Chưa ghi nhận xe của gia đình. Sắp xếp và xác nhận phương tiện cùng hỗ trợ phù hợp từ trước.",
        "confirmTransport": "Xác nhận phương tiện, khả năng tiếp cận và thời gian khởi hành theo hướng dẫn địa phương."
    ]
}
