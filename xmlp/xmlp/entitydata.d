module xmlp.xmlp.entitydata;

/// This enum classification is confusing and partly redundent with RefTagType
enum EntityType { Parameter, General, Notation }
/// This enum classification is confusing and partly redundent with EntityType

enum RefTagType { UNKNOWN_REF, ENTITY_REF, SYSTEM_REF, NOTATION_REF}


/// Entities can have PUBLIC and SYSTEM identities
struct ExternalID
{
    string publicId_;
    string systemId_;
}



/// Keeps track of value and processing status of external or internal entities.
class EntityData
{
    enum
    {
        Unknown, Found, Expanded, Failed
    }
    int				status_;				// unknown, found, expanded or failed
    string			name_;				// key for AA lookup
    string			value_;				// processed value
    ExternalID		src_;				// public and system id
    EntityType		etype_;				// Parameter, General or Notation?
    RefTagType		reftype_;			// SYSTEM or what?

    bool			isInternal_;	// This was defined in the internal subset of DTD

    string			encoding_;		// original encoding?
    string			version_;	//
    string			ndataref_;		// name of notation data, if any

    //Notation		ndata_;         // if we are a notation, here is whatever it is
    string			baseDir_;		// if was found, where was it?
    EntityData		context_;		// if the entity was declared in another entity

    this(string id, EntityType et)
    {
        name_ = id;
        etype_ = et;
        status_ = EntityData.Unknown;
    }
}


version (CustomAA)
{
    import alt.arraymap;
    alias HashTable!(string, EntityData)	EntityDataMap;

}
else
{
    alias EntityData[string]	EntityDataMap;

}


