/*******************************************************************************
 * PushButton Engine
 * Copyright (C) 2009 PushButton Labs, LLC
 * For more information see http://www.pushbuttonengine.com
 * 
 * This file is licensed under the terms of the MIT license, which is included
 * in the License.html file at the root directory of this SDK.
 ******************************************************************************/
package com.pblabs.engine.entity
{
   /**
    * Allocates an instance of the hidden Entity class. This should be
    * used anytime an IEntity object needs to be created. Encapsulating
    * the Entity class forces code to use IEntity rather than Entity when
    * dealing with entity references. This will ensure that code is future
    * proof as well as allow the Entity class to be pooled in the future.
    * 
    * @return A new IEntity.
    */
   public function allocateEntity():IEntity
   {
      return new Entity();
   }
}

import com.pblabs.engine.entity.IEntity;
import com.pblabs.engine.entity.IEntityComponent;
import com.pblabs.engine.entity.PropertyReference;
import com.pblabs.engine.core.NameManager;
import com.pblabs.engine.core.TemplateManager;
import com.pblabs.engine.debug.Logger;
import com.pblabs.engine.debug.Profiler;
import com.pblabs.engine.serialization.Serializer;
import com.pblabs.engine.serialization.TypeUtility;

import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IEventDispatcher;
import flash.utils.Dictionary;

class Entity extends EventDispatcher implements IEntity
{
   public function get name():String
   {
      return _name;
   }
   
   public function get eventDispatcher():IEventDispatcher
   {
      return this as IEventDispatcher;
   }
   
   public function initialize(name:String, alias:String = null):void
   {
      _name = name;
      if (_name == null || _name == "")
         return;
      
      _alias = alias;
         
      NameManager.instance.addEntity(this, _name);
      if(_alias)
         NameManager.instance.addEntity(this, _alias);
   }
   
   public function destroy():void
   {
      // Give listeners a chance to act before we start destroying stuff.
      dispatchEvent(new Event("EntityDestroyed"));
      
      // Get out of the NameManager.
      NameManager.instance.removeEntity(this);
      _name = null;
      
      // Unregister our components.
      for each(var component:IEntityComponent in _components)
         component.unregister();
      
      // And remove their references from the dictionary.
      for (var name:String in _components)
         delete _components[name];
   }
   
   public function serialize(xml:XML):void
   {
      for each (var component:IEntityComponent in _components)
      {
         var componentXML:XML = new XML(<Component/>);
         Serializer.instance.serialize(component, componentXML);
         xml.appendChild(componentXML);
      }
   }
   
   public function deserialize(xml:XML, registerComponents:Boolean = true):void
   {
      // Note what entity we're deserializing to the Serializer.
      Serializer.instance.setCurrentEntity(this);
      
      for each (var componentXML:XML in xml.*)
      {
         // Error if it's an unexpected tag.
         if(componentXML.name().toString().toLowerCase() != "component")
         {
            Logger.printError(this, "deserialize", "Found unexpected tag '" + componentXML.name().toString() + "', only <component/> is valid, ignoring tag. Error in entity '" + name + "'.");
            continue;
         }
         
         var componentName:String = componentXML.attribute("name");
         var componentClassName:String = componentXML.attribute("type");
         var component:IEntityComponent = null;
         
         if (componentClassName.length > 0)
         {
            component = TypeUtility.instantiate(componentClassName) as IEntityComponent;
            if (!component)
            {
               Logger.printError(this, "deserialize", "Unable to instantiate component " + componentName + " of type " + componentClassName + " on entity '" + name + "'.");
               continue;
            }
            
            if (!doAddComponent(component, componentName))
               continue;
         }
         else
         {
            component = lookupComponentByName(componentName);
            if (!component)
            {
               Logger.printError(this, "deserialize", "No type specified for the component " + componentName + " and the component doesn't exist on a parent template for entity '" + name + "'.");
               continue;
            }
         }
         
         Serializer.instance.deserialize(component, componentXML);
      }
      
      if (registerComponents)
      {
         doRegisterComponents();
         doResetComponents();
      }
   }
   
   public function addComponent(component:IEntityComponent, componentName:String):void
   {
      if (!doAddComponent(component, componentName))
         return;
      
      component.register(this, componentName);
      doResetComponents();
   }
   
   public function removeComponent(component:IEntityComponent):void
   {
      if (!doRemoveComponent(component))
         return;
      
      component.unregister();
      doResetComponents();
   }
   
   public function lookupComponentByType(componentType:Class):IEntityComponent
   {
      for each(var component:IEntityComponent in _components)
      {
         if (component is componentType)
            return component;
      }
      
      return null;
   }
   
   public function lookupComponentsByType(componentType:Class):Array
   {
      var list:Array = new Array();
      
      for each(var component:IEntityComponent in _components)
      {
         if (component is componentType)
            list.push(component);
      }
      
      return list;
   }
   
   public function lookupComponentByName(componentName:String):IEntityComponent
   {
      return _components[componentName];
   }
   
   public function doesPropertyExist(property:PropertyReference):Boolean
   {
      return findProperty(property, false, _tempPropertyInfo, true) != null;
   }
   
   public function getProperty(property:PropertyReference):*
   {
      // Look up the property.
      var info:PropertyInfo = findProperty(property, false, _tempPropertyInfo);
      var result:* = null;
      
      // Get value if any.
      if (info)
         result = info.getValue();

      // Clean up to avoid dangling references.
      _tempPropertyInfo.clear();
      
      return result;
   }
   
   public function setProperty(property:PropertyReference, value:*):void
   {
      // Look up and set.
      var info:PropertyInfo = findProperty(property, true, _tempPropertyInfo);
      if (info)
         info.setValue(value);

      // Clean up to avoid dangling references.
      _tempPropertyInfo.clear();
   }
   
   private function doAddComponent(component:IEntityComponent, componentName:String):Boolean
   {
      if (component.owner)
      {
         Logger.printError(this, "AddComponent", "The component " + componentName + " already has an owner. (" + name + ")");
         return false;
      }
      
      if (_components[componentName])
      {
         Logger.printError(this, "AddComponent", "A component with name " + componentName + " already exists on this entity (" + name + ").");
         return false;
      }
      
      _components[componentName] = component;
      return true;
   }
   
   private function doRemoveComponent(component:IEntityComponent):Boolean
   {
      if (component.owner != this)
      {
         Logger.printError(this, "AddComponent", "The component " + component.name + " is not owned by this entity. (" + name + ")");
         return false;
      }
      
      if (!_components[component.name])
      {
         Logger.printError(this, "AddComponent", "The component " + component.name + " was not found on this entity. (" + name + ")");
         return false;
      }
      
      delete _components[component.name];
      return true;
   }
   
   /**
    * Register any unregistered components on this entity. Useful when you are
    * deferring registration (for instance due to template processing).
    */
   private function doRegisterComponents():void
   {
      for (var name:String in _components)
      {
         // Skip ones we have already registered.
         if(_components[name].isRegistered)
            continue;
         
         _components[name].register(this, name);
      }
   }
   
   private function doResetComponents():void
   {
      for each(var component:IEntityComponent in _components)
         component.reset();
   }

   private function findProperty(reference:PropertyReference, willSet:Boolean = false, providedPi:PropertyInfo = null, suppressErrors:Boolean = false):PropertyInfo
   {
      // TODO: we use appendChild but relookup the results, can we just use return value?
      
      // Early out if we got a null property reference.
      if (!reference || reference.property == null || reference.property == "")
         return null;

      Profiler.enter("Entity.findProperty");
      
      // Must have a propertyInfo to operate with.
      if(!providedPi)
         providedPi = new PropertyInfo();
      
      // Cached lookups apply only to components.
      if(reference.cachedLookup && reference.cachedLookup.length > 0)
      {
         var cl:Array = reference.cachedLookup;
         var cachedWalk:* = lookupComponentByName(cl[0]);
         if(!cachedWalk)
         {
            if(!suppressErrors)
               Logger.printWarning(this, "findProperty", "Could not resolve component named '" + cl[0] + "' for property '" + reference.property + "' with cached reference. " + Logger.getCallStack());
            Profiler.exit("Entity.findProperty");
            return null;
         }
         
         for(var i:int = 1; i<cl.length - 1; i++)
         {
            cachedWalk = cachedWalk[cl[i]];
            if(cachedWalk == null)
            {
               if(!suppressErrors)
                  Logger.printWarning(this, "findProperty", "Could not resolve property '" + cl[i] + "' for property reference '" + reference.property + "' with cached reference"  + Logger.getCallStack());
               Profiler.exit("Entity.findProperty");
               return null;
            }
         }
         
         var cachedPi:PropertyInfo = providedPi;
         cachedPi.propertyParent = cachedWalk;
         cachedPi.propertyName = cl[cl.length-1];
         Profiler.exit("Entity.findProperty");
         return cachedPi;
      }
      
      // Split up the property reference.      
      var propertyName:String = reference.property;
      var path:Array = propertyName.split(".");
      
      // Distinguish if it is a component reference (@), named object ref (#), or
      // an XML reference (!), and look up the first element in the path.
      var isTemplateXML:Boolean = false;
      var itemName:String = path[0];
      var curIdx:int = 1;
      var startChar:String = itemName.charAt(0);
      var curLookup:String = itemName.slice(1);
      var parentElem:*;
      if(startChar == "@")
      {
         // Component reference, look up the component by name.
         parentElem = lookupComponentByName(curLookup);
         if(!parentElem)
         {
            Logger.printWarning(this, "findProperty", "Could not resolve component named '" + curLookup + "' for property '" + reference.property + "'");
            Profiler.exit("Entity.findProperty");
            return null;
         }
         
         // Cache the split out string.
         path[0] = curLookup;
         reference.cachedLookup = path;
      }
      else if(startChar == "#")
      {
         // Named object reference. Look up the entity in the NameManager.
         parentElem = NameManager.instance.lookup(curLookup);
         if(!parentElem)
         {
            Logger.printWarning(this, "findProperty", "Could not resolve named object named '" + curLookup + "' for property '" + reference.property + "'");
            Profiler.exit("Entity.findProperty");
            return null;
         }
         
         // Get the component on it.
         curIdx++;
         curLookup = path[1];
         var comLookup:IEntityComponent = (parentElem as IEntity).lookupComponentByName(curLookup);
         if(!comLookup)
         {
            Logger.printWarning(this, "findProperty", "Could not find component '" + curLookup + "' on named entity '" + (parentElem as IEntity).name + "' for property '" + reference.property + "'");
            Profiler.exit("Entity.findProperty");
            return null;
         }
         parentElem = comLookup;
      }
      else if(startChar == "!")
      {
         // XML reference. Look it up inside the TemplateManager. We only support
         // templates and entities - no groups.
         parentElem = TemplateManager.instance.getXML(curLookup, "template", "entity");
         if(!parentElem)
         {
            Logger.printWarning(this, "findProperty", "Could not find XML named '" + curLookup + "' for property '" + reference.property + "'");
            Profiler.exit("Entity.findProperty");
            return null;
         }
         
         // Try to find the specified component.
         curIdx++;
         var nextElem:* = null;
         for each(var cTag:* in parentElem.*)
         {
            if(cTag.@name == path[1])
            {
               nextElem = cTag;
               break;
            }
         }
         
         // Create it if appropriate.
         if(!nextElem && willSet)
         {
            // Create component tag.
            (parentElem as XML).appendChild(<component name={path[1]}/>);
            
            // Look it up again.
            for each(cTag in parentElem.*)
            {
               if(cTag.@name == path[1])
               {
                  nextElem = cTag;
                  break;
               }
            }
         }
         
         // Error if we don't have it!
         if(!nextElem)
         {
            Logger.printWarning(this, "findProperty", "Could not find component '" + path[1] + "' in XML template '" + path[0].slice(1) + "' for property '" + reference.property + "'");
            Profiler.exit("Entity.findProperty");
            return null;
         }
         
         // Get ready to search the rest.
         parentElem = nextElem;
         
         // Indicate we are dealing with xml.
         isTemplateXML = true;
      }
      else
      {
         Logger.printWarning(this, "findProperty", "Got a property path that doesn't start with !, #, or @. Started with '" + startChar + "' for property '" + reference.property + "'");
         Profiler.exit("Entity.findProperty");
         return null;
      }

      // Make sure we have a field to look up.
      if(curIdx < path.length)
         curLookup = path[curIdx++] as String;
      else
         curLookup = null;
      
      // Do the remainder of the look up.
      while(curIdx < path.length && parentElem)
      {
         // Try the next element in the path.
         var oldParentElem:* = parentElem;
         try
         {
            if(parentElem is XML || parentElem is XMLList)
               parentElem = parentElem.child(curLookup);
            else
               parentElem = parentElem[curLookup];
         }
         catch(e:Error)
         {
            parentElem = null;
         }
         
         // Several different possibilities that indicate we failed to advance.
         var gotEmpty:Boolean = false;
         if(parentElem == undefined) gotEmpty = true;
         if(parentElem == null) gotEmpty = true;
         if(parentElem is XMLList && parentElem.length() == 0) gotEmpty = true;
         
         // If we're going to set and it's XML, create the field.
         if(willSet && isTemplateXML && gotEmpty && oldParentElem)
         {
            oldParentElem.appendChild(<{curLookup}/>);
            parentElem = oldParentElem.child(curLookup);
            gotEmpty = false;
         }
         
         if(gotEmpty)
         {
            Logger.printWarning(this, "findProperty", "Could not resolve property '" + curLookup + "' for property reference '" + reference.property + "'");
            Profiler.exit("Entity.findProperty");
            return null;
         }
         
         // Advance to next element in the path.
         curLookup = path[curIdx++] as String;
      }
      
      // Did we end up with a match?
      if(parentElem)
      {
         var pi:PropertyInfo = providedPi;
         pi.propertyParent = parentElem;
         pi.propertyName = curLookup;
         Profiler.exit("Entity.findProperty");
         return pi;
      }
      
      Profiler.exit("Entity.findProperty");
      return null;
   }
   
   private var _name:String = null;
   private var _alias:String = null;
   private var _components:Dictionary = new Dictionary();
   private var _tempPropertyInfo:PropertyInfo = new PropertyInfo();
}

class PropertyInfo
{
   public var propertyParent:Object = null;
   public var propertyName:String = null;
   
   public function getValue():*
   {
      try
      {
         return propertyParent[propertyName];
      }
      catch(e:Error)
      {
         return null;
      }
   }
   
   public function setValue(value:*):void
   {
      propertyParent[propertyName] = value;
   }
   
   public function clear():void
   {
      propertyParent = null;
      propertyName = null;
   }
}