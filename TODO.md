[x] Format coords and rotation (round axis values to three decimal places).
[x] Quick UI hide/show UI. F.e. entity menu.
[x] Add icons to buttons for quick recognition (Ped Options, Animations, Attach, Freeze Position). 
[x] Add the ability to copy entity ID.
[x] Add the ability to copy entity coordinates.
[x] Add the ability to copy entity rotation.

[x] Add the ability to copy camera coordinates and rotation.

[x] Add the ability to copy entity attachment settings as native (AttachEntity)
[x] Add the ability to search bones in Attachments menu.

[x] Copy animation parameters as native (PlayAnimation -> print('TaskPlayAnim', json.encode(anim)))
[x] Implement an animation playback tab for objects.


[x] Improve ped cloning. Clone completely with all clothes components.
[x] Fix ped cloning issue in interiors. Seds should align with the ground instead of causing cursor/camera flickering.

[] Preview spawn object https://github.com/keeganwut/spooner and https://github.com/kibook/spooner/pull/19/files
https://gyazo.com/2dc97757d4bd16b871ef651e84421013
[] Switch UI selection with arrow buttons (faster entity preview)

[] Plants (rdr2) https://github.com/zetafe1/spooner_plants

[] Optimize data in props list for faster display and search 
[] Option to display bone names and if possible draw skeleton lines on entity
[] Add Gizmo for advanced object placement https://github.com/GlitchOo/gs_gizmo

[] Performance (store hashes) https://github.com/kibook/spooner/pull/51/files

[] Fix issues: https://github.com/kibook/spooner/issues:
- Entity moving towards camera [x]
- Light options changes all entities
- Gang members hostile to each other
- Scenario keep restarting
- Update list of objects
- Not usable in ESX and QB
- Vehicle mods not saving into DB

[x] GetInteriorAtCoords (Show interior ID and Room)


[x] apply force to enity
ApplyForceToEntityCenterOfMass(1918467, 1, 0, 0.0, 5.0, false, false, true, false)


[] фикс поворот клонированных педов на C/V(они возвращаются на место автомато почему-то)
- Не удаётся пофиксить

[] регулирование скорости не только на кнопки но и на колесо мышки как раньше
[] копирование координат как vec4 вместе с heading

[x] клонирование машин (отключение коллизии на время выделения объекта / при выделении чтобы не сталкивались)
- Entity moving towards camera
- Fix ped cloning issue in interiors. Seds should align with the ground instead of causing cursor/camera flickering.

[x] Фикс регулирования скорости передвижения объекта (на '[' и ']' не работает)
- Всё работает. Нужно просто переключить режим на букву 'R'

Маппинг:
[] Клонирование объекта на ту же позицию
[] Выделение объекта перед тем как его двигать (отключение фрикамеры по дефолту)
[] Gizmo
[] Фикс спауна объекта в море (отклчить спаун объекта по рейкасту, сделать спаун перед камерой в оффесете)
